#!/usr/bin/env python3
"""
Evidence Validation Script
Validates evidence artifacts against JSON schema
"""

import json
import sys
from pathlib import Path
from typing import Dict, Any, List
import logging

try:
    import jsonschema
    from jsonschema import validate, ValidationError
except ImportError:
    print("ERROR: jsonschema not installed. Run: pip install jsonschema")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class EvidenceValidator:
    """Validate evidence artifacts against schema"""

    def __init__(self, schema_path: str = "/home/notme/Desktop/gitea/evidence-collection/schemas/evidence-artifact-schema.json"):
        """Initialize validator with schema"""
        self.schema = self._load_schema(schema_path)

    def _load_schema(self, schema_path: str) -> Dict[str, Any]:
        """Load JSON schema"""
        try:
            with open(schema_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load schema from {schema_path}: {e}")
            raise

    def validate_file(self, filepath: str) -> Dict[str, Any]:
        """Validate single evidence file"""
        logger.info(f"Validating: {filepath}")

        try:
            with open(filepath, 'r') as f:
                evidence = json.load(f)

            # Validate against schema
            validate(instance=evidence, schema=self.schema)

            logger.info(f"  ✓ Valid: {filepath}")
            return {
                "file": filepath,
                "valid": True,
                "errors": [],
            }

        except ValidationError as e:
            logger.error(f"  ✗ Invalid: {filepath}")
            logger.error(f"    {e.message}")
            return {
                "file": filepath,
                "valid": False,
                "errors": [e.message],
            }

        except Exception as e:
            logger.error(f"  ✗ Error reading {filepath}: {e}")
            return {
                "file": filepath,
                "valid": False,
                "errors": [str(e)],
            }

    def validate_directory(self, dirpath: str) -> Dict[str, Any]:
        """Validate all evidence files in directory"""
        logger.info(f"Validating directory: {dirpath}")

        dir_path = Path(dirpath)
        results = []

        if not dir_path.exists():
            logger.error(f"Directory does not exist: {dirpath}")
            return {
                "success": False,
                "error": f"Directory not found: {dirpath}",
            }

        # Find all JSON files
        json_files = list(dir_path.rglob("*.json"))

        # Filter out summaries and manifests
        evidence_files = [
            f for f in json_files
            if "summary" not in f.name.lower() and "manifest" not in f.name.lower()
        ]

        logger.info(f"Found {len(evidence_files)} evidence files")

        for filepath in evidence_files:
            result = self.validate_file(str(filepath))
            results.append(result)

        # Summary
        valid_count = sum(1 for r in results if r["valid"])
        invalid_count = len(results) - valid_count

        summary = {
            "success": True,
            "total_files": len(results),
            "valid_files": valid_count,
            "invalid_files": invalid_count,
            "results": results,
        }

        return summary


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="Validate evidence artifacts against schema")
    parser.add_argument('--file', help='Validate single file')
    parser.add_argument('--directory', help='Validate all files in directory')
    parser.add_argument('--schema', default='/home/notme/Desktop/gitea/evidence-collection/schemas/evidence-artifact-schema.json',
                        help='Path to JSON schema')
    parser.add_argument('--output', help='Output validation report to JSON file')

    args = parser.parse_args()

    if not args.file and not args.directory:
        parser.error("Must specify either --file or --directory")

    validator = EvidenceValidator(schema_path=args.schema)

    if args.file:
        result = validator.validate_file(args.file)
        summary = {
            "total_files": 1,
            "valid_files": 1 if result["valid"] else 0,
            "invalid_files": 0 if result["valid"] else 1,
            "results": [result],
        }
    else:
        summary = validator.validate_directory(args.directory)

    # Print summary
    print(f"\n=== Validation Summary ===")
    print(f"Total files: {summary['total_files']}")
    print(f"Valid: {summary['valid_files']}")
    print(f"Invalid: {summary['invalid_files']}")

    if summary['invalid_files'] > 0:
        print(f"\nInvalid files:")
        for result in summary['results']:
            if not result['valid']:
                print(f"  - {result['file']}")
                for error in result['errors']:
                    print(f"    Error: {error}")

    # Save report if requested
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(summary, f, indent=2)
        print(f"\nValidation report saved to {args.output}")

    # Exit with error if any invalid files
    if summary['invalid_files'] > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
