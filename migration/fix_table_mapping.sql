-- =====================================================
-- Fix Table Name Mapping for Archon
-- =====================================================
-- This script creates views that map the table names
-- expected by the application to the actual table names
-- with the archon_ prefix
-- =====================================================

-- Drop existing views if they exist
DROP VIEW IF EXISTS sources CASCADE;
DROP VIEW IF EXISTS documents CASCADE;
DROP VIEW IF EXISTS code_examples CASCADE;
DROP VIEW IF EXISTS projects CASCADE;
DROP VIEW IF EXISTS tasks CASCADE;
DROP VIEW IF EXISTS project_sources CASCADE;
DROP VIEW IF EXISTS document_versions CASCADE;
DROP VIEW IF EXISTS prompts CASCADE;
DROP VIEW IF EXISTS settings CASCADE;

-- Create views that map to the archon_ prefixed tables
CREATE OR REPLACE VIEW sources AS 
SELECT * FROM archon_sources;

-- Map documents to archon_crawled_pages (this is the critical one)
CREATE OR REPLACE VIEW documents AS 
SELECT 
    id,
    source_id,
    content,
    metadata,
    embedding,
    created_at,
    updated_at,
    -- Add any missing columns that the app expects
    chunk_index,
    total_chunks,
    title,
    url,
    summary,
    cleaned_content,
    original_content,
    contextual_summary,
    contextual_embedding
FROM archon_crawled_pages;

CREATE OR REPLACE VIEW code_examples AS 
SELECT * FROM archon_code_examples;

CREATE OR REPLACE VIEW projects AS 
SELECT * FROM archon_projects;

CREATE OR REPLACE VIEW tasks AS 
SELECT * FROM archon_tasks;

CREATE OR REPLACE VIEW project_sources AS 
SELECT * FROM archon_project_sources;

CREATE OR REPLACE VIEW document_versions AS 
SELECT * FROM archon_document_versions;

CREATE OR REPLACE VIEW prompts AS 
SELECT * FROM archon_prompts;

-- Settings might be referenced without prefix
CREATE OR REPLACE VIEW settings AS 
SELECT * FROM archon_settings;

-- Grant appropriate permissions
GRANT ALL ON sources TO authenticated, service_role;
GRANT ALL ON documents TO authenticated, service_role;
GRANT ALL ON code_examples TO authenticated, service_role;
GRANT ALL ON projects TO authenticated, service_role;
GRANT ALL ON tasks TO authenticated, service_role;
GRANT ALL ON project_sources TO authenticated, service_role;
GRANT ALL ON document_versions TO authenticated, service_role;
GRANT ALL ON prompts TO authenticated, service_role;
GRANT ALL ON settings TO authenticated, service_role;

-- Create insert/update/delete rules for the views to make them fully functional
-- This allows the application to insert/update/delete through the views

-- Sources view rules
CREATE OR REPLACE RULE sources_insert AS ON INSERT TO sources 
DO INSTEAD INSERT INTO archon_sources VALUES (NEW.*);

CREATE OR REPLACE RULE sources_update AS ON UPDATE TO sources 
DO INSTEAD UPDATE archon_sources SET 
    source_id = NEW.source_id,
    url = NEW.url,
    summary = NEW.summary,
    total_word_count = NEW.total_word_count,
    title = NEW.title,
    source_type = NEW.source_type,
    description = NEW.description,
    created_at = NEW.created_at,
    updated_at = NEW.updated_at,
    metadata = NEW.metadata,
    last_crawled_at = NEW.last_crawled_at,
    crawl_status = NEW.crawl_status,
    error_message = NEW.error_message
WHERE source_id = OLD.source_id;

CREATE OR REPLACE RULE sources_delete AS ON DELETE TO sources 
DO INSTEAD DELETE FROM archon_sources WHERE source_id = OLD.source_id;

-- Documents (archon_crawled_pages) view rules
CREATE OR REPLACE RULE documents_insert AS ON INSERT TO documents 
DO INSTEAD INSERT INTO archon_crawled_pages VALUES (NEW.*);

CREATE OR REPLACE RULE documents_update AS ON UPDATE TO documents 
DO INSTEAD UPDATE archon_crawled_pages SET 
    id = NEW.id,
    source_id = NEW.source_id,
    content = NEW.content,
    metadata = NEW.metadata,
    embedding = NEW.embedding,
    created_at = NEW.created_at,
    updated_at = NEW.updated_at,
    chunk_index = NEW.chunk_index,
    total_chunks = NEW.total_chunks,
    title = NEW.title,
    url = NEW.url,
    summary = NEW.summary,
    cleaned_content = NEW.cleaned_content,
    original_content = NEW.original_content,
    contextual_summary = NEW.contextual_summary,
    contextual_embedding = NEW.contextual_embedding
WHERE id = OLD.id;

CREATE OR REPLACE RULE documents_delete AS ON DELETE TO documents 
DO INSTEAD DELETE FROM archon_crawled_pages WHERE id = OLD.id;

-- Code examples view rules
CREATE OR REPLACE RULE code_examples_insert AS ON INSERT TO code_examples 
DO INSTEAD INSERT INTO archon_code_examples VALUES (NEW.*);

CREATE OR REPLACE RULE code_examples_update AS ON UPDATE TO code_examples 
DO INSTEAD UPDATE archon_code_examples SET 
    id = NEW.id,
    source_id = NEW.source_id,
    language = NEW.language,
    code = NEW.code,
    summary = NEW.summary,
    metadata = NEW.metadata,
    embedding = NEW.embedding,
    created_at = NEW.created_at,
    url = NEW.url,
    title = NEW.title,
    description = NEW.description,
    example_type = NEW.example_type,
    file_path = NEW.file_path,
    start_line = NEW.start_line,
    end_line = NEW.end_line,
    is_complete = NEW.is_complete
WHERE id = OLD.id;

CREATE OR REPLACE RULE code_examples_delete AS ON DELETE TO code_examples 
DO INSTEAD DELETE FROM archon_code_examples WHERE id = OLD.id;

-- Verify the views work
SELECT 'Views created successfully!' as status;

-- Test counts
SELECT 
    (SELECT COUNT(*) FROM sources) as sources_count,
    (SELECT COUNT(*) FROM documents) as documents_count,
    (SELECT COUNT(*) FROM code_examples) as code_examples_count;