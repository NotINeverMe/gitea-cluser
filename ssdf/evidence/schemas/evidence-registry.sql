-- SSDF Evidence Registry Database Schema
-- PostgreSQL 14+

-- Create database
-- CREATE DATABASE compliance;

-- Connect to database
\c compliance;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create evidence registry table
CREATE TABLE IF NOT EXISTS evidence_registry (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Build identification
    repository VARCHAR(255) NOT NULL,
    commit_sha VARCHAR(40) NOT NULL,
    workflow_id BIGINT,
    run_number INTEGER,
    branch VARCHAR(255) DEFAULT 'main',

    -- SSDF compliance
    practices_covered TEXT[] NOT NULL,
    practices_count INTEGER GENERATED ALWAYS AS (array_length(practices_covered, 1)) STORED,

    -- Evidence storage
    evidence_path VARCHAR(512) NOT NULL UNIQUE,
    evidence_hash VARCHAR(64) NOT NULL,
    evidence_size BIGINT,

    -- Timestamps
    collected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    retention_until TIMESTAMP WITH TIME ZONE,

    -- Metadata
    tools_used JSONB,
    attestations JSONB,
    metadata JSONB,

    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes for efficient querying
CREATE INDEX idx_evidence_repository ON evidence_registry(repository);
CREATE INDEX idx_evidence_commit_sha ON evidence_registry(commit_sha);
CREATE INDEX idx_evidence_collected_at ON evidence_registry(collected_at DESC);
CREATE INDEX idx_evidence_practices ON evidence_registry USING GIN(practices_covered);
CREATE INDEX idx_evidence_tools ON evidence_registry USING GIN(tools_used);
CREATE INDEX idx_evidence_retention ON evidence_registry(retention_until) WHERE retention_until IS NOT NULL;

-- Create practice coverage table for detailed tracking
CREATE TABLE IF NOT EXISTS practice_coverage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    evidence_id UUID NOT NULL REFERENCES evidence_registry(id) ON DELETE CASCADE,

    -- Practice details
    practice_id VARCHAR(10) NOT NULL,
    practice_group VARCHAR(5) NOT NULL,
    practice_title VARCHAR(255),

    -- Evidence mapping
    tool_name VARCHAR(100) NOT NULL,
    evidence_file VARCHAR(255) NOT NULL,
    verification_method TEXT,

    -- Status
    status VARCHAR(20) DEFAULT 'covered',
    verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    verified_by VARCHAR(255),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(evidence_id, practice_id, tool_name)
);

-- Create indexes for practice coverage
CREATE INDEX idx_practice_coverage_evidence ON practice_coverage(evidence_id);
CREATE INDEX idx_practice_coverage_practice ON practice_coverage(practice_id);
CREATE INDEX idx_practice_coverage_tool ON practice_coverage(tool_name);
CREATE INDEX idx_practice_coverage_group ON practice_coverage(practice_group);

-- Create tools table for tracking tool usage
CREATE TABLE IF NOT EXISTS tools_inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Tool details
    tool_name VARCHAR(100) NOT NULL UNIQUE,
    tool_type VARCHAR(50),
    tool_version VARCHAR(50),

    -- Usage statistics
    usage_count INTEGER DEFAULT 0,
    first_used TIMESTAMP WITH TIME ZONE,
    last_used TIMESTAMP WITH TIME ZONE,

    -- Configuration
    config JSONB,
    practices_supported TEXT[],

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create compliance summary view
CREATE OR REPLACE VIEW compliance_summary AS
SELECT
    repository,
    COUNT(DISTINCT id) as total_builds,
    COUNT(DISTINCT commit_sha) as total_commits,
    AVG(practices_count) as avg_practices_per_build,
    MAX(practices_count) as max_practices,
    MIN(practices_count) as min_practices,
    MIN(collected_at) as first_evidence,
    MAX(collected_at) as last_evidence,
    COUNT(DISTINCT unnest(practices_covered)) as unique_practices_covered
FROM evidence_registry
GROUP BY repository;

-- Create practice frequency view
CREATE OR REPLACE VIEW practice_frequency AS
SELECT
    unnest(practices_covered) as practice_id,
    COUNT(*) as frequency,
    COUNT(DISTINCT repository) as repository_count,
    MIN(collected_at) as first_occurrence,
    MAX(collected_at) as last_occurrence
FROM evidence_registry
GROUP BY practice_id
ORDER BY frequency DESC;

-- Create tool usage view
CREATE OR REPLACE VIEW tool_usage AS
SELECT
    tool_name,
    COUNT(*) as evidence_count,
    COUNT(DISTINCT evidence_id) as unique_builds,
    COUNT(DISTINCT practice_id) as practices_covered,
    MIN(created_at) as first_used,
    MAX(created_at) as last_used
FROM practice_coverage
GROUP BY tool_name
ORDER BY evidence_count DESC;

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for evidence_registry
CREATE TRIGGER update_evidence_registry_updated_at
    BEFORE UPDATE ON evidence_registry
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create trigger for tools_inventory
CREATE TRIGGER update_tools_inventory_updated_at
    BEFORE UPDATE ON tools_inventory
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create function to calculate retention date
CREATE OR REPLACE FUNCTION calculate_retention_date(
    collected_date TIMESTAMP WITH TIME ZONE,
    retention_days INTEGER DEFAULT 2555
)
RETURNS TIMESTAMP WITH TIME ZONE AS $$
BEGIN
    RETURN collected_date + (retention_days || ' days')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

-- Create function to get coverage statistics
CREATE OR REPLACE FUNCTION get_coverage_stats(
    p_repository VARCHAR DEFAULT NULL,
    p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE(
    total_builds BIGINT,
    total_repositories BIGINT,
    avg_practices NUMERIC,
    unique_practices BIGINT,
    coverage_percent NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(DISTINCT er.id)::BIGINT as total_builds,
        COUNT(DISTINCT er.repository)::BIGINT as total_repositories,
        ROUND(AVG(er.practices_count), 2) as avg_practices,
        COUNT(DISTINCT unnest(er.practices_covered))::BIGINT as unique_practices,
        ROUND((COUNT(DISTINCT unnest(er.practices_covered))::NUMERIC / 42) * 100, 2) as coverage_percent
    FROM evidence_registry er
    WHERE
        (p_repository IS NULL OR er.repository = p_repository)
        AND (p_start_date IS NULL OR er.collected_at >= p_start_date)
        AND (p_end_date IS NULL OR er.collected_at <= p_end_date);
END;
$$ LANGUAGE plpgsql;

-- Create function to find missing practices
CREATE OR REPLACE FUNCTION find_missing_practices(
    p_repository VARCHAR,
    p_all_practices TEXT[] DEFAULT ARRAY[
        'PO.1.1', 'PO.1.2', 'PO.1.3', 'PO.2.1', 'PO.2.2', 'PO.3.1', 'PO.3.2',
        'PO.4.1', 'PO.5.1', 'PO.5.2', 'PS.1.1', 'PS.2.1', 'PS.3.1', 'PS.3.2',
        'PW.1.1', 'PW.1.2', 'PW.1.3', 'PW.2.1', 'PW.4.1', 'PW.4.4', 'PW.5.1',
        'PW.6.1', 'PW.6.2', 'PW.7.1', 'PW.7.2', 'PW.8.1', 'PW.8.2', 'PW.9.1',
        'PW.9.2', 'RV.1.1', 'RV.1.2', 'RV.1.3', 'RV.2.1', 'RV.2.2', 'RV.3.1',
        'RV.3.2', 'RV.3.3'
    ]
)
RETURNS TABLE(
    practice_id TEXT,
    last_covered TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.practice,
        MAX(er.collected_at) as last_covered
    FROM unnest(p_all_practices) as p(practice)
    LEFT JOIN evidence_registry er ON
        p.practice = ANY(er.practices_covered)
        AND er.repository = p_repository
    GROUP BY p.practice
    HAVING MAX(er.collected_at) IS NULL
    ORDER BY p.practice;
END;
$$ LANGUAGE plpgsql;

-- Insert sample SSDF practices reference
CREATE TABLE IF NOT EXISTS ssdf_practices_reference (
    practice_id VARCHAR(10) PRIMARY KEY,
    practice_group VARCHAR(5) NOT NULL,
    practice_title VARCHAR(255) NOT NULL,
    practice_description TEXT,
    practice_level VARCHAR(20),

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Insert SSDF practice definitions
INSERT INTO ssdf_practices_reference (practice_id, practice_group, practice_title, practice_description, practice_level) VALUES
-- Prepare the Organization (PO)
('PO.1.1', 'PO', 'Identify and document security requirements', 'Define security requirements for software development', 'basic'),
('PO.1.2', 'PO', 'Communicate requirements to developers', 'Ensure developers understand security requirements', 'basic'),
('PO.3.1', 'PO', 'Implement automated build processes', 'Use automated tools for building and integrating software', 'basic'),
('PO.3.2', 'PO', 'Build from version-controlled code', 'Ensure all builds use code from version control', 'basic'),
('PO.5.1', 'PO', 'Implement secure coding practices', 'Follow secure coding standards and guidelines', 'basic'),

-- Protect the Software (PS)
('PS.1.1', 'PS', 'Store and protect code and artifacts', 'Securely store source code and build artifacts', 'basic'),
('PS.2.1', 'PS', 'Provide integrity verification mechanism', 'Sign software and provide verification methods', 'basic'),
('PS.3.1', 'PS', 'Archive and protect records', 'Maintain records of software provenance and security', 'basic'),

-- Produce Well-Secured Software (PW)
('PW.1.1', 'PW', 'Design software securely', 'Incorporate security into software design', 'basic'),
('PW.4.1', 'PW', 'Review code for security issues', 'Perform code reviews with security focus', 'basic'),
('PW.4.4', 'PW', 'Review third-party components', 'Assess security of third-party dependencies', 'basic'),
('PW.5.1', 'PW', 'Test for security weaknesses', 'Conduct security testing during development', 'basic'),
('PW.6.1', 'PW', 'Use automated SAST tools', 'Employ static application security testing', 'intermediate'),
('PW.6.2', 'PW', 'Use automated DAST tools', 'Employ dynamic application security testing', 'intermediate'),
('PW.7.1', 'PW', 'Review and address code findings', 'Triage and remediate identified vulnerabilities', 'basic'),
('PW.8.1', 'PW', 'Scan for known vulnerabilities', 'Check dependencies for known security issues', 'intermediate'),
('PW.8.2', 'PW', 'Track and remediate vulnerabilities', 'Maintain vulnerability inventory and remediation', 'intermediate'),
('PW.9.1', 'PW', 'Generate SBOM', 'Create software bill of materials', 'intermediate'),
('PW.9.2', 'PW', 'Distribute SBOM', 'Make SBOM available to stakeholders', 'intermediate'),

-- Respond to Vulnerabilities (RV)
('RV.1.1', 'RV', 'Monitor for vulnerabilities', 'Continuously monitor for new threats', 'basic'),
('RV.1.2', 'RV', 'Identify affected software', 'Determine scope of vulnerability impact', 'basic'),
('RV.2.1', 'RV', 'Analyze vulnerabilities', 'Assess severity and impact of findings', 'basic'),
('RV.2.2', 'RV', 'Prioritize remediation', 'Rank vulnerabilities for remediation', 'basic'),
('RV.3.1', 'RV', 'Remediate vulnerabilities', 'Fix or mitigate identified issues', 'basic'),
('RV.3.3', 'RV', 'Distribute fixed software', 'Release patched versions to users', 'basic')
ON CONFLICT (practice_id) DO NOTHING;

-- Create role for evidence collector
CREATE ROLE evidence_collector WITH LOGIN PASSWORD 'change_this_password';
GRANT SELECT, INSERT, UPDATE ON evidence_registry TO evidence_collector;
GRANT SELECT, INSERT, UPDATE ON practice_coverage TO evidence_collector;
GRANT SELECT, INSERT, UPDATE ON tools_inventory TO evidence_collector;
GRANT SELECT ON compliance_summary TO evidence_collector;
GRANT SELECT ON practice_frequency TO evidence_collector;
GRANT SELECT ON tool_usage TO evidence_collector;
GRANT SELECT ON ssdf_practices_reference TO evidence_collector;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO evidence_collector;

-- Create role for evidence query
CREATE ROLE evidence_query WITH LOGIN PASSWORD 'change_this_password';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO evidence_query;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO evidence_query;

-- Comments
COMMENT ON TABLE evidence_registry IS 'Registry of SSDF compliance evidence collected from CI/CD pipelines';
COMMENT ON TABLE practice_coverage IS 'Detailed tracking of SSDF practice coverage per build';
COMMENT ON TABLE tools_inventory IS 'Inventory of security tools used for evidence collection';
COMMENT ON TABLE ssdf_practices_reference IS 'Reference table for SSDF practice definitions';

COMMENT ON COLUMN evidence_registry.practices_covered IS 'Array of SSDF practice IDs covered by this evidence';
COMMENT ON COLUMN evidence_registry.evidence_path IS 'GCS path to evidence package';
COMMENT ON COLUMN evidence_registry.evidence_hash IS 'SHA-256 hash of evidence package';
COMMENT ON COLUMN evidence_registry.retention_until IS 'Date when evidence can be deleted (7 years from collection)';
COMMENT ON COLUMN evidence_registry.tools_used IS 'JSON object mapping tools to their usage in this build';
