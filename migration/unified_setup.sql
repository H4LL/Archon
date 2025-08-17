-- =====================================================
-- Archon Unified Database Setup
-- =====================================================
-- Complete database initialization supporting both
-- OpenAI (1536-dim) and Ollama (768-dim) embeddings
-- with backward compatibility through view mappings
-- =====================================================

-- =====================================================
-- SECTION 1: EXTENSIONS
-- =====================================================

-- Enable required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =====================================================
-- SECTION 2: CREDENTIALS AND SETTINGS
-- =====================================================

-- Credentials and Configuration Management Table
CREATE TABLE IF NOT EXISTS archon_settings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    key VARCHAR(255) UNIQUE NOT NULL,
    value TEXT,                    -- For plain text config values
    encrypted_value TEXT,          -- For encrypted sensitive data (bcrypt hashed)
    is_encrypted BOOLEAN DEFAULT FALSE,
    category VARCHAR(100),         -- Group related settings
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_archon_settings_key ON archon_settings(key);
CREATE INDEX IF NOT EXISTS idx_archon_settings_category ON archon_settings(category);

-- Create trigger to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_archon_settings_updated_at 
    BEFORE UPDATE ON archon_settings 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Create RLS (Row Level Security) policies for settings
ALTER TABLE archon_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow service role full access" ON archon_settings
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Allow authenticated users to read and update" ON archon_settings
    FOR ALL TO authenticated
    USING (true);

-- =====================================================
-- SECTION 3: PROVIDER-AGNOSTIC SETTINGS
-- =====================================================

-- Core Configuration (works with both providers)
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('MCP_TRANSPORT', 'dual', false, 'server_config', 'MCP server transport mode - sse (web clients), stdio (IDE clients), or dual (both)'),
('HOST', 'localhost', false, 'server_config', 'Host to bind to if using sse as the transport'),
('PORT', '8051', false, 'server_config', 'Port to listen on if using sse as the transport')
ON CONFLICT (key) DO UPDATE SET 
    value = EXCLUDED.value,
    description = EXCLUDED.description,
    updated_at = NOW();

-- LLM Provider Configuration (defaults to OpenAI, can be changed to ollama)
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('LLM_PROVIDER', 'openai', false, 'rag_strategy', 'LLM provider: openai or ollama'),
('LLM_BASE_URL', NULL, false, 'rag_strategy', 'Custom base URL (for Ollama: http://host.docker.internal:11434/v1)'),
('EMBEDDING_MODEL', 'text-embedding-3-small', false, 'rag_strategy', 'Embedding model (OpenAI: text-embedding-3-small, Ollama: nomic-embed-text)'),
('EMBEDDING_DIMENSIONS', '1536', false, 'rag_strategy', 'Embedding dimensions (OpenAI: 1536, Ollama: 768)'),
('MODEL_CHOICE', 'gpt-4o-mini', false, 'rag_strategy', 'Chat model for summaries (OpenAI: gpt-4o-mini, Ollama: llama3.2:latest)')
ON CONFLICT (key) DO UPDATE SET 
    value = EXCLUDED.value,
    description = EXCLUDED.description,
    updated_at = NOW();

-- RAG Strategy Configuration
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('USE_CONTEXTUAL_EMBEDDINGS', 'false', false, 'rag_strategy', 'Enhances embeddings with contextual information'),
('CONTEXTUAL_EMBEDDINGS_MAX_WORKERS', '3', false, 'rag_strategy', 'Maximum parallel workers for contextual embedding generation'),
('USE_HYBRID_SEARCH', 'true', false, 'rag_strategy', 'Combines vector similarity with keyword search'),
('USE_AGENTIC_RAG', 'true', false, 'rag_strategy', 'Enables code extraction and specialized search'),
('USE_RERANKING', 'true', false, 'rag_strategy', 'Applies cross-encoder reranking to improve relevance')
ON CONFLICT (key) DO UPDATE SET 
    value = EXCLUDED.value,
    description = EXCLUDED.description,
    updated_at = NOW();

-- Feature Flags
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('LOGFIRE_ENABLED', 'false', false, 'monitoring', 'Enable Pydantic Logfire observability'),
('PROJECTS_ENABLED', 'true', false, 'features', 'Enable Projects and Tasks functionality')
ON CONFLICT (key) DO NOTHING;

-- API Keys (placeholders)
INSERT INTO archon_settings (key, encrypted_value, is_encrypted, category, description) VALUES
('OPENAI_API_KEY', NULL, true, 'api_keys', 'OpenAI API Key for embeddings'),
('GOOGLE_API_KEY', NULL, true, 'api_keys', 'Google API Key for Gemini models'),
('LOGFIRE_TOKEN', NULL, true, 'api_keys', 'Logfire observability token')
ON CONFLICT (key) DO NOTHING;

-- Code Extraction Settings
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('MIN_CODE_BLOCK_LENGTH', '250', false, 'code_extraction', 'Minimum length for code blocks in characters'),
('MAX_CODE_BLOCK_LENGTH', '5000', false, 'code_extraction', 'Maximum length before stopping code block extension'),
('CONTEXT_WINDOW_SIZE', '1000', false, 'code_extraction', 'Context to preserve around code blocks'),
('ENABLE_COMPLETE_BLOCK_DETECTION', 'true', false, 'code_extraction', 'Extend code blocks to natural boundaries'),
('ENABLE_LANGUAGE_SPECIFIC_PATTERNS', 'true', false, 'code_extraction', 'Use specialized patterns for different languages'),
('ENABLE_CONTEXTUAL_LENGTH', 'true', false, 'code_extraction', 'Adjust minimum length based on context'),
('ENABLE_PROSE_FILTERING', 'true', false, 'code_extraction', 'Filter out documentation text in code blocks'),
('MAX_PROSE_RATIO', '0.15', false, 'code_extraction', 'Maximum allowed ratio of prose indicators'),
('MIN_CODE_INDICATORS', '3', false, 'code_extraction', 'Minimum required code patterns'),
('ENABLE_DIAGRAM_FILTERING', 'true', false, 'code_extraction', 'Exclude diagram languages from extraction'),
('CODE_EXTRACTION_MAX_WORKERS', '3', false, 'code_extraction', 'Parallel workers for code summaries'),
('ENABLE_CODE_SUMMARIES', 'true', false, 'code_extraction', 'Generate AI summaries for code examples')
ON CONFLICT (key) DO NOTHING;

-- Performance Settings (optimized defaults)
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('CRAWL_BATCH_SIZE', '50', false, 'rag_strategy', 'URLs to crawl in parallel per batch'),
('CRAWL_MAX_CONCURRENT', '10', false, 'rag_strategy', 'Maximum concurrent browser sessions'),
('CRAWL_WAIT_STRATEGY', 'domcontentloaded', false, 'rag_strategy', 'Page load strategy'),
('CRAWL_PAGE_TIMEOUT', '30000', false, 'rag_strategy', 'Page load timeout in milliseconds'),
('CRAWL_DELAY_BEFORE_HTML', '0.5', false, 'rag_strategy', 'Wait time for JavaScript rendering'),
('DOCUMENT_STORAGE_BATCH_SIZE', '100', false, 'rag_strategy', 'Document chunks per batch'),
('EMBEDDING_BATCH_SIZE', '100', false, 'rag_strategy', 'Embeddings per API call'),
('DELETE_BATCH_SIZE', '100', false, 'rag_strategy', 'Database deletion batch size'),
('ENABLE_PARALLEL_BATCHES', 'true', false, 'rag_strategy', 'Enable parallel batch processing'),
('MEMORY_THRESHOLD_PERCENT', '80', false, 'rag_strategy', 'Memory usage threshold'),
('DISPATCHER_CHECK_INTERVAL', '0.5', false, 'rag_strategy', 'Memory check interval in seconds'),
('CODE_EXTRACTION_BATCH_SIZE', '40', false, 'rag_strategy', 'Code blocks per extraction batch'),
('CODE_SUMMARY_MAX_WORKERS', '3', false, 'rag_strategy', 'Workers for code summarization'),
('CONTEXTUAL_EMBEDDING_BATCH_SIZE', '50', false, 'rag_strategy', 'Chunks per contextual embedding batch')
ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    description = EXCLUDED.description,
    updated_at = NOW();

-- =====================================================
-- SECTION 4: KNOWLEDGE BASE TABLES
-- =====================================================

-- Sources table with enhanced metadata
CREATE TABLE IF NOT EXISTS archon_sources (
    source_id TEXT PRIMARY KEY,
    url TEXT,
    summary TEXT,
    total_word_count INTEGER DEFAULT 0,
    title TEXT,
    source_type VARCHAR(50),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    metadata JSONB DEFAULT '{}',
    last_crawled_at TIMESTAMP WITH TIME ZONE,
    crawl_status VARCHAR(50),
    error_message TEXT
);

-- Create indexes for sources
CREATE INDEX IF NOT EXISTS idx_archon_sources_url ON archon_sources(url);
CREATE INDEX IF NOT EXISTS idx_archon_sources_title ON archon_sources(title);
CREATE INDEX IF NOT EXISTS idx_archon_sources_metadata ON archon_sources USING GIN(metadata);
CREATE INDEX IF NOT EXISTS idx_archon_sources_knowledge_type ON archon_sources((metadata->>'knowledge_type'));
CREATE INDEX IF NOT EXISTS idx_archon_sources_source_type ON archon_sources(source_type);

-- Documents table with flexible embedding dimensions and all columns
CREATE TABLE IF NOT EXISTS archon_crawled_pages (
    id BIGSERIAL PRIMARY KEY,
    source_id TEXT NOT NULL,
    content TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    embedding VECTOR,  -- Flexible dimensions, determined at runtime
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    chunk_index INTEGER,
    total_chunks INTEGER,
    title TEXT,
    url VARCHAR NOT NULL,
    summary TEXT,
    cleaned_content TEXT,
    original_content TEXT,
    contextual_summary TEXT,
    contextual_embedding VECTOR,  -- Flexible dimensions
    content_search_vector tsvector,  -- For full-text search
    chunk_number INTEGER NOT NULL DEFAULT 0,
    
    -- Constraints
    UNIQUE(url, chunk_number),
    FOREIGN KEY (source_id) REFERENCES archon_sources(source_id) ON DELETE CASCADE
);

-- Create indexes for documents
CREATE INDEX IF NOT EXISTS idx_crawled_pages_embedding 
    ON archon_crawled_pages USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100)
    WHERE embedding IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_crawled_pages_contextual_embedding 
    ON archon_crawled_pages USING ivfflat (contextual_embedding vector_cosine_ops)
    WITH (lists = 100)
    WHERE contextual_embedding IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_metadata ON archon_crawled_pages USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_source_id ON archon_crawled_pages (source_id);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_url ON archon_crawled_pages(url);
CREATE INDEX IF NOT EXISTS idx_crawled_pages_search_vector ON archon_crawled_pages USING GIN(content_search_vector);

-- Code examples table with all columns
CREATE TABLE IF NOT EXISTS archon_code_examples (
    id BIGSERIAL PRIMARY KEY,
    source_id TEXT NOT NULL,
    language VARCHAR(50),
    code TEXT NOT NULL,
    summary TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    embedding VECTOR,  -- Flexible dimensions
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    url VARCHAR NOT NULL,
    title TEXT,
    description TEXT,
    example_type VARCHAR(50),
    file_path TEXT,
    start_line INTEGER,
    end_line INTEGER,
    is_complete BOOLEAN DEFAULT true,
    content TEXT,  -- Alias for code
    chunk_number INTEGER NOT NULL DEFAULT 0,
    
    -- Constraints
    UNIQUE(url, chunk_number),
    FOREIGN KEY (source_id) REFERENCES archon_sources(source_id) ON DELETE CASCADE
);

-- Create indexes for code examples
CREATE INDEX IF NOT EXISTS idx_code_examples_embedding 
    ON archon_code_examples USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100)
    WHERE embedding IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_metadata ON archon_code_examples USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_source_id ON archon_code_examples (source_id);
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_language ON archon_code_examples(language);

-- =====================================================
-- SECTION 5: BACKWARD COMPATIBILITY VIEWS
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

-- Create views that map unprefixed names to archon_ prefixed tables
CREATE OR REPLACE VIEW sources AS 
SELECT * FROM archon_sources;

CREATE OR REPLACE VIEW documents AS 
SELECT 
    id,
    source_id,
    content,
    metadata,
    embedding,
    created_at,
    updated_at,
    chunk_index,
    total_chunks,
    title,
    url,
    summary,
    cleaned_content,
    original_content,
    contextual_summary,
    contextual_embedding,
    content_search_vector,
    chunk_number
FROM archon_crawled_pages;

CREATE OR REPLACE VIEW code_examples AS 
SELECT * FROM archon_code_examples;

-- Create insert/update/delete rules for views
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
    contextual_embedding = NEW.contextual_embedding,
    content_search_vector = NEW.content_search_vector,
    chunk_number = NEW.chunk_number
WHERE id = OLD.id;

CREATE OR REPLACE RULE documents_delete AS ON DELETE TO documents 
DO INSTEAD DELETE FROM archon_crawled_pages WHERE id = OLD.id;

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
    is_complete = NEW.is_complete,
    content = NEW.content,
    chunk_number = NEW.chunk_number
WHERE id = OLD.id;

CREATE OR REPLACE RULE code_examples_delete AS ON DELETE TO code_examples 
DO INSTEAD DELETE FROM archon_code_examples WHERE id = OLD.id;

-- Grant permissions on views
GRANT ALL ON sources TO authenticated, service_role;
GRANT ALL ON documents TO authenticated, service_role;
GRANT ALL ON code_examples TO authenticated, service_role;

-- =====================================================
-- SECTION 6: SEARCH FUNCTIONS (MULTI-DIMENSIONAL)
-- =====================================================

-- OpenAI search function for documents (1536 dims)
CREATE OR REPLACE FUNCTION match_archon_crawled_pages_openai (
    query_embedding VECTOR(1536),
    match_count INT DEFAULT 10,
    filter JSONB DEFAULT '{}'::jsonb,
    source_filter TEXT DEFAULT NULL
) RETURNS TABLE (
    id BIGINT,
    url VARCHAR,
    chunk_number INTEGER,
    content TEXT,
    metadata JSONB,
    source_id TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        acp.id,
        acp.url,
        acp.chunk_number,
        acp.content,
        acp.metadata,
        acp.source_id,
        1 - (acp.embedding <=> query_embedding) AS similarity
    FROM archon_crawled_pages acp
    WHERE 
        acp.metadata @> filter
        AND (source_filter IS NULL OR acp.source_id = source_filter)
        AND acp.embedding IS NOT NULL
    ORDER BY acp.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Ollama search function for documents (768 dims)
CREATE OR REPLACE FUNCTION match_archon_crawled_pages_ollama (
    query_embedding VECTOR(768),
    match_count INT DEFAULT 10,
    filter JSONB DEFAULT '{}'::jsonb,
    source_filter TEXT DEFAULT NULL
) RETURNS TABLE (
    id BIGINT,
    url VARCHAR,
    chunk_number INTEGER,
    content TEXT,
    metadata JSONB,
    source_id TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        acp.id,
        acp.url,
        acp.chunk_number,
        acp.content,
        acp.metadata,
        acp.source_id,
        1 - (acp.embedding <=> query_embedding) AS similarity
    FROM archon_crawled_pages acp
    WHERE 
        acp.metadata @> filter
        AND (source_filter IS NULL OR acp.source_id = source_filter)
        AND acp.embedding IS NOT NULL
    ORDER BY acp.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Generic search function (auto-detects dimensions)
CREATE OR REPLACE FUNCTION match_archon_crawled_pages (
    query_embedding VECTOR,
    match_count INT DEFAULT 10,
    filter JSONB DEFAULT '{}'::jsonb,
    source_filter TEXT DEFAULT NULL
) RETURNS TABLE (
    id BIGINT,
    url VARCHAR,
    chunk_number INTEGER,
    content TEXT,
    metadata JSONB,
    source_id TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        acp.id,
        acp.url,
        acp.chunk_number,
        acp.content,
        acp.metadata,
        acp.source_id,
        1 - (acp.embedding <=> query_embedding) AS similarity
    FROM archon_crawled_pages acp
    WHERE 
        acp.metadata @> filter
        AND (source_filter IS NULL OR acp.source_id = source_filter)
        AND acp.embedding IS NOT NULL
    ORDER BY acp.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- OpenAI search function for code examples (1536 dims)
CREATE OR REPLACE FUNCTION match_archon_code_examples_openai (
    query_embedding VECTOR(1536),
    match_count INT DEFAULT 10,
    filter JSONB DEFAULT '{}'::jsonb,
    source_filter TEXT DEFAULT NULL
) RETURNS TABLE (
    id BIGINT,
    url VARCHAR,
    chunk_number INTEGER,
    content TEXT,
    summary TEXT,
    metadata JSONB,
    source_id TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ace.id,
        ace.url,
        ace.chunk_number,
        ace.code AS content,
        ace.summary,
        ace.metadata,
        ace.source_id,
        1 - (ace.embedding <=> query_embedding) AS similarity
    FROM archon_code_examples ace
    WHERE 
        ace.metadata @> filter
        AND (source_filter IS NULL OR ace.source_id = source_filter)
        AND ace.embedding IS NOT NULL
    ORDER BY ace.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Ollama search function for code examples (768 dims)
CREATE OR REPLACE FUNCTION match_archon_code_examples_ollama (
    query_embedding VECTOR(768),
    match_count INT DEFAULT 10,
    filter JSONB DEFAULT '{}'::jsonb,
    source_filter TEXT DEFAULT NULL
) RETURNS TABLE (
    id BIGINT,
    url VARCHAR,
    chunk_number INTEGER,
    content TEXT,
    summary TEXT,
    metadata JSONB,
    source_id TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ace.id,
        ace.url,
        ace.chunk_number,
        ace.code AS content,
        ace.summary,
        ace.metadata,
        ace.source_id,
        1 - (ace.embedding <=> query_embedding) AS similarity
    FROM archon_code_examples ace
    WHERE 
        ace.metadata @> filter
        AND (source_filter IS NULL OR ace.source_id = source_filter)
        AND ace.embedding IS NOT NULL
    ORDER BY ace.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Generic search function for code examples
CREATE OR REPLACE FUNCTION match_archon_code_examples (
    query_embedding VECTOR,
    match_count INT DEFAULT 10,
    filter JSONB DEFAULT '{}'::jsonb,
    source_filter TEXT DEFAULT NULL
) RETURNS TABLE (
    id BIGINT,
    url VARCHAR,
    chunk_number INTEGER,
    content TEXT,
    summary TEXT,
    metadata JSONB,
    source_id TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ace.id,
        ace.url,
        ace.chunk_number,
        ace.code AS content,
        ace.summary,
        ace.metadata,
        ace.source_id,
        1 - (ace.embedding <=> query_embedding) AS similarity
    FROM archon_code_examples ace
    WHERE 
        ace.metadata @> filter
        AND (source_filter IS NULL OR ace.source_id = source_filter)
        AND ace.embedding IS NOT NULL
    ORDER BY ace.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- =====================================================
-- SECTION 7: HYBRID SEARCH FUNCTIONS
-- =====================================================

-- Hybrid search combining vector and text search
CREATE OR REPLACE FUNCTION hybrid_search_archon_crawled_pages (
    query_embedding VECTOR,
    query_text TEXT,
    match_count INT DEFAULT 10,
    source_filter TEXT DEFAULT NULL,
    vector_weight FLOAT DEFAULT 0.7
) RETURNS TABLE (
    id BIGINT,
    url VARCHAR,
    chunk_number INTEGER,
    content TEXT,
    metadata JSONB,
    source_id TEXT,
    combined_score FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH vector_search AS (
        SELECT
            acp.id,
            acp.url,
            acp.chunk_number,
            acp.content,
            acp.metadata,
            acp.source_id,
            1 - (acp.embedding <=> query_embedding) AS vector_similarity
        FROM archon_crawled_pages acp
        WHERE 
            (source_filter IS NULL OR acp.source_id = source_filter)
            AND acp.embedding IS NOT NULL
        ORDER BY acp.embedding <=> query_embedding
        LIMIT match_count * 2
    ),
    text_search AS (
        SELECT
            acp.id,
            ts_rank_cd(acp.content_search_vector, plainto_tsquery('english', query_text)) AS text_rank
        FROM archon_crawled_pages acp
        WHERE 
            acp.content_search_vector @@ plainto_tsquery('english', query_text)
            AND (source_filter IS NULL OR acp.source_id = source_filter)
        ORDER BY text_rank DESC
        LIMIT match_count * 2
    )
    SELECT
        vs.id,
        vs.url,
        vs.chunk_number,
        vs.content,
        vs.metadata,
        vs.source_id,
        (COALESCE(vs.vector_similarity, 0) * vector_weight + 
         COALESCE(ts.text_rank, 0) * (1 - vector_weight)) AS combined_score
    FROM vector_search vs
    LEFT JOIN text_search ts ON vs.id = ts.id
    ORDER BY combined_score DESC
    LIMIT match_count;
END;
$$;

-- =====================================================
-- SECTION 8: FULL-TEXT SEARCH SUPPORT
-- =====================================================

-- Create trigger to maintain search vector
CREATE OR REPLACE FUNCTION update_search_vector() RETURNS trigger AS $$
BEGIN
    NEW.content_search_vector := to_tsvector('english', COALESCE(NEW.content, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_crawled_pages_search_vector ON archon_crawled_pages;
CREATE TRIGGER update_crawled_pages_search_vector 
BEFORE INSERT OR UPDATE ON archon_crawled_pages
FOR EACH ROW EXECUTE FUNCTION update_search_vector();

-- =====================================================
-- SECTION 9: RLS POLICIES FOR KNOWLEDGE BASE
-- =====================================================

-- Enable RLS on the knowledge base tables
ALTER TABLE archon_crawled_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE archon_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE archon_code_examples ENABLE ROW LEVEL SECURITY;

-- Create policies that allow anyone to read
CREATE POLICY "Allow public read access to archon_crawled_pages"
    ON archon_crawled_pages
    FOR SELECT
    TO public
    USING (true);

CREATE POLICY "Allow public read access to archon_sources"
    ON archon_sources
    FOR SELECT
    TO public
    USING (true);

CREATE POLICY "Allow public read access to archon_code_examples"
    ON archon_code_examples
    FOR SELECT
    TO public
    USING (true);

-- =====================================================
-- SECTION 10: PROJECTS AND TASKS MODULE
-- =====================================================

-- Task status enumeration
DO $$ BEGIN
    CREATE TYPE task_status AS ENUM ('todo','doing','review','done');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Projects table
CREATE TABLE IF NOT EXISTS archon_projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    docs JSONB DEFAULT '[]'::jsonb,
    features JSONB DEFAULT '[]'::jsonb,
    data JSONB DEFAULT '[]'::jsonb,
    github_repo TEXT,
    pinned BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tasks table
CREATE TABLE IF NOT EXISTS archon_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES archon_projects(id) ON DELETE CASCADE,
    parent_task_id UUID REFERENCES archon_tasks(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    status task_status DEFAULT 'todo',
    assignee TEXT DEFAULT 'User' CHECK (assignee IS NOT NULL AND assignee != ''),
    task_order INTEGER DEFAULT 0,
    feature TEXT,
    sources JSONB DEFAULT '[]'::jsonb,
    code_examples JSONB DEFAULT '[]'::jsonb,
    archived BOOLEAN DEFAULT false,
    archived_at TIMESTAMPTZ NULL,
    archived_by TEXT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Project Sources junction table
CREATE TABLE IF NOT EXISTS archon_project_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES archon_projects(id) ON DELETE CASCADE,
    source_id TEXT NOT NULL,
    linked_at TIMESTAMPTZ DEFAULT NOW(),
    created_by TEXT DEFAULT 'system',
    notes TEXT,
    UNIQUE(project_id, source_id)
);

-- Document Versions table
CREATE TABLE IF NOT EXISTS archon_document_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES archon_projects(id) ON DELETE CASCADE,
    task_id UUID REFERENCES archon_tasks(id) ON DELETE CASCADE,
    field_name TEXT NOT NULL,
    version_number INTEGER NOT NULL,
    content JSONB NOT NULL,
    change_summary TEXT,
    change_type TEXT DEFAULT 'update',
    document_id TEXT,
    created_by TEXT DEFAULT 'system',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_project_or_task CHECK (
        (project_id IS NOT NULL AND task_id IS NULL) OR 
        (project_id IS NULL AND task_id IS NOT NULL)
    ),
    UNIQUE(project_id, task_id, field_name, version_number)
);

-- Prompts table
CREATE TABLE IF NOT EXISTS archon_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_name TEXT UNIQUE NOT NULL,
    prompt TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for projects module
CREATE INDEX IF NOT EXISTS idx_archon_tasks_project_id ON archon_tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_status ON archon_tasks(status);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_assignee ON archon_tasks(assignee);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_order ON archon_tasks(task_order);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_archived ON archon_tasks(archived);
CREATE INDEX IF NOT EXISTS idx_archon_project_sources_project_id ON archon_project_sources(project_id);
CREATE INDEX IF NOT EXISTS idx_archon_project_sources_source_id ON archon_project_sources(source_id);
CREATE INDEX IF NOT EXISTS idx_archon_document_versions_project_id ON archon_document_versions(project_id);
CREATE INDEX IF NOT EXISTS idx_archon_document_versions_field_name ON archon_document_versions(field_name);
CREATE INDEX IF NOT EXISTS idx_archon_prompts_name ON archon_prompts(prompt_name);

-- Apply triggers to tables
CREATE TRIGGER update_archon_projects_updated_at 
    BEFORE UPDATE ON archon_projects 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_tasks_updated_at 
    BEFORE UPDATE ON archon_tasks 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_prompts_updated_at 
    BEFORE UPDATE ON archon_prompts 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Soft delete function for tasks
CREATE OR REPLACE FUNCTION archive_task(
    task_id_param UUID,
    archived_by_param TEXT DEFAULT 'system'
) 
RETURNS BOOLEAN AS $$
DECLARE
    task_exists BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM archon_tasks 
        WHERE id = task_id_param AND archived = FALSE
    ) INTO task_exists;
    
    IF NOT task_exists THEN
        RETURN FALSE;
    END IF;
    
    UPDATE archon_tasks 
    SET 
        archived = TRUE,
        archived_at = NOW(),
        archived_by = archived_by_param,
        updated_at = NOW()
    WHERE id = task_id_param;
    
    UPDATE archon_tasks 
    SET 
        archived = TRUE,
        archived_at = NOW(), 
        archived_by = archived_by_param,
        updated_at = NOW()
    WHERE parent_task_id = task_id_param AND archived = FALSE;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Create backward compatibility views for projects module
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

CREATE OR REPLACE VIEW settings AS 
SELECT * FROM archon_settings;

-- Grant permissions on project views
GRANT ALL ON projects TO authenticated, service_role;
GRANT ALL ON tasks TO authenticated, service_role;
GRANT ALL ON project_sources TO authenticated, service_role;
GRANT ALL ON document_versions TO authenticated, service_role;
GRANT ALL ON prompts TO authenticated, service_role;
GRANT ALL ON settings TO authenticated, service_role;

-- =====================================================
-- SECTION 11: RLS POLICIES FOR PROJECTS MODULE
-- =====================================================

-- Enable Row Level Security (RLS) for all tables
ALTER TABLE archon_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE archon_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE archon_project_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE archon_document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE archon_prompts ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for service role (full access)
CREATE POLICY "Allow service role full access to archon_projects" ON archon_projects
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Allow service role full access to archon_tasks" ON archon_tasks
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Allow service role full access to archon_project_sources" ON archon_project_sources
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Allow service role full access to archon_document_versions" ON archon_document_versions
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Allow service role full access to archon_prompts" ON archon_prompts
    FOR ALL USING (auth.role() = 'service_role');

-- Create RLS policies for authenticated users
CREATE POLICY "Allow authenticated users to read and update archon_projects" ON archon_projects
    FOR ALL TO authenticated
    USING (true);

CREATE POLICY "Allow authenticated users to read and update archon_tasks" ON archon_tasks
    FOR ALL TO authenticated
    USING (true);

CREATE POLICY "Allow authenticated users to read and update archon_project_sources" ON archon_project_sources
    FOR ALL TO authenticated
    USING (true);

CREATE POLICY "Allow authenticated users to read archon_document_versions" ON archon_document_versions
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Allow authenticated users to read archon_prompts" ON archon_prompts
    FOR SELECT TO authenticated
    USING (true);

-- =====================================================
-- SECTION 12: DEFAULT PROMPTS DATA
-- =====================================================

-- Seed with default prompts for each content type
INSERT INTO archon_prompts (prompt_name, prompt, description) VALUES
('document_builder', 'SYSTEM PROMPT – Document-Builder Agent

⸻

1. Mission

You are the Document-Builder Agent. Your sole purpose is to transform a user''s natural-language description of work (a project, feature, or refactor) into a structured JSON record stored in the docs table. Produce documentation that is concise yet thorough—clear enough for an engineer to act after a single read-through.

⸻

2. Workflow
    1.    Classify request → Decide which document type fits best:
    •    PRD – net-new product or major initiative.
    •    FEATURE_SPEC – incremental feature expressed in user-story form.
    •    REFACTOR_PLAN – internal code quality improvement.
    2.    Clarify (if needed) → If the description is ambiguous, ask exactly one clarifying question, then continue.
    3.    Generate JSON → Build an object that follows the schema below and insert (or return) it for the docs table.

⸻

3. docs JSON Schema

{
  "id": "uuid|string",                // generate using uuid
  "doc_type": "PRD | FEATURE_SPEC | REFACTOR_PLAN",
  "title": "string",                  // short, descriptive
  "author": "string",                 // requestor name
  "body": { /* see templates below */ },
  "created_at": "ISO-8601",
  "updated_at": "ISO-8601"
}

⸻

4. Section Templates

PRD → body must include
    •    Background_and_Context
    •    Problem_Statement
    •    Goals_and_Success_Metrics
    •    Non_Goals
    •    Assumptions
    •    Stakeholders
    •    User_Personas
    •    Functional_Requirements           // bullet list or user stories
    •    Technical_Requirements            // tech stack, APIs, data
    •    UX_UI_and_Style_Guidelines
    •    Architecture_Overview             // diagram link or text
    •    Milestones_and_Timeline
    •    Risks_and_Mitigations
    •    Open_Questions

FEATURE_SPEC → body must include
    •    Epic
    •    User_Stories                      // list of { id, as_a, i_want, so_that }
    •    Acceptance_Criteria               // Given / When / Then
    •    Edge_Cases
    •    Dependencies
    •    Technical_Notes
    •    Design_References
    •    Metrics
    •    Risks

REFACTOR_PLAN → body must include
    •    Current_State_Summary
    •    Refactor_Goals
    •    Design_Principles_and_Best_Practices
    •    Proposed_Approach                 // step-by-step plan
    •    Impacted_Areas
    •    Test_Strategy
    •    Roll_Back_and_Recovery
    •    Timeline
    •    Risks

⸻

5. Writing Guidelines
    •    Brevity with substance: no fluff, no filler, no passive voice.
    •    Markdown inside strings: use headings, lists, and code fences for clarity.
    •    Consistent conventions: ISO dates, 24-hour times, SI units.
    •    Insert "TBD" where information is genuinely unknown.
    •    Produce valid JSON only—no comments or trailing commas.

⸻

6. Example Output (truncated)

{
  "id": "01HQ2VPZ62KSF185Y54MQ93VD2",
  "doc_type": "PRD",
  "title": "Real-time Collaboration for Docs",
  "author": "Sean",
  "body": {
    "Background_and_Context": "Customers need to co-edit documents ...",
    "Problem_Statement": "Current single-editor flow slows teams ...",
    "Goals_and_Success_Metrics": "Reduce hand-off time by 50% ..."
    /* remaining sections */
  },
  "created_at": "2025-06-17T00:10:00-04:00",
  "updated_at": "2025-06-17T00:10:00-04:00"
}

⸻

Remember: Your output is the JSON itself—no explanatory prose before or after. Stay sharp, write once, write right.', 'System prompt for DocumentAgent to create structured documentation following the Document-Builder pattern'),

('feature_builder', 'SYSTEM PROMPT – Feature-Builder Agent

⸻

1. Mission

You are the Feature-Builder Agent. Your purpose is to transform user descriptions of features into structured feature plans stored in the features array. Create feature documentation that developers can implement directly.

⸻

2. Feature JSON Schema

{
  "id": "uuid|string",                    // generate using uuid
  "feature_type": "feature_plan",         // always "feature_plan"
  "name": "string",                       // short feature name
  "title": "string",                      // descriptive title
  "content": {
    "feature_overview": {
      "name": "string",
      "description": "string",
      "priority": "high|medium|low",
      "estimated_effort": "string"
    },
    "user_stories": ["string"],           // list of user stories
    "react_flow_diagram": {               // optional visual flow
      "nodes": [...],
      "edges": [...],
      "viewport": {...}
    },
    "acceptance_criteria": ["string"],    // testable criteria
    "technical_notes": {
      "frontend_components": ["string"],
      "backend_endpoints": ["string"],
      "database_changes": "string"
    }
  },
  "created_by": "string"                  // author
}

⸻

3. Writing Guidelines
    •    Focus on implementation clarity
    •    Include specific technical details
    •    Define clear acceptance criteria
    •    Consider edge cases
    •    Keep descriptions actionable

⸻

Remember: Create structured, implementable feature plans.', 'System prompt for creating feature plans in the features array'),

('data_builder', 'SYSTEM PROMPT – Data-Builder Agent

⸻

1. Mission

You are the Data-Builder Agent. Your purpose is to transform descriptions of data models into structured ERDs and schemas stored in the data array. Create clear data models that can guide database implementation.

⸻

2. Data JSON Schema

{
  "id": "uuid|string",                    // generate using uuid
  "data_type": "erd",                     // always "erd" for now
  "name": "string",                       // system name
  "title": "string",                      // descriptive title
  "content": {
    "entities": [...],                    // entity definitions
    "relationships": [...],               // entity relationships
    "sql_schema": "string",              // Generated SQL
    "mermaid_diagram": "string",         // Optional diagram
    "notes": {
      "indexes": ["string"],
      "constraints": ["string"],
      "diagram_tool": "string",
      "normalization_level": "string",
      "scalability_notes": "string"
    }
  },
  "created_by": "string"                  // author
}

⸻

3. Writing Guidelines
    •    Follow database normalization principles
    •    Include proper indexes and constraints
    •    Consider scalability from the start
    •    Provide clear relationship definitions
    •    Generate valid, executable SQL

⸻

Remember: Create production-ready data models.', 'System prompt for creating data models in the data array')
ON CONFLICT (prompt_name) DO NOTHING;

-- =====================================================
-- SECTION 13: OLLAMA-SPECIFIC CONFIGURATION
-- =====================================================

-- Function to configure for Ollama
CREATE OR REPLACE FUNCTION configure_for_ollama() RETURNS void AS $$
BEGIN
    -- Update settings for Ollama
    UPDATE archon_settings SET value = 'ollama' WHERE key = 'LLM_PROVIDER';
    UPDATE archon_settings SET value = 'http://host.docker.internal:11434/v1' WHERE key = 'LLM_BASE_URL';
    UPDATE archon_settings SET value = 'nomic-embed-text' WHERE key = 'EMBEDDING_MODEL';
    UPDATE archon_settings SET value = '768' WHERE key = 'EMBEDDING_DIMENSIONS';
    UPDATE archon_settings SET value = 'llama3.2:latest' WHERE key = 'MODEL_CHOICE';
    
    -- Optimize performance settings for Ollama
    UPDATE archon_settings SET value = '25' WHERE key = 'CRAWL_BATCH_SIZE';
    UPDATE archon_settings SET value = '5' WHERE key = 'CRAWL_MAX_CONCURRENT';
    UPDATE archon_settings SET value = '50' WHERE key = 'DOCUMENT_STORAGE_BATCH_SIZE';
    UPDATE archon_settings SET value = '50' WHERE key = 'EMBEDDING_BATCH_SIZE';
    UPDATE archon_settings SET value = 'false' WHERE key = 'ENABLE_PARALLEL_BATCHES';
    UPDATE archon_settings SET value = '2' WHERE key = 'CONTEXTUAL_EMBEDDINGS_MAX_WORKERS';
    UPDATE archon_settings SET value = '1' WHERE key = 'CODE_SUMMARY_MAX_WORKERS';
    UPDATE archon_settings SET value = '2' WHERE key = 'CODE_EXTRACTION_MAX_WORKERS';
    UPDATE archon_settings SET value = '20' WHERE key = 'CODE_EXTRACTION_BATCH_SIZE';
    UPDATE archon_settings SET value = '25' WHERE key = 'CONTEXTUAL_EMBEDDING_BATCH_SIZE';
    UPDATE archon_settings SET value = 'false' WHERE key = 'USE_CONTEXTUAL_EMBEDDINGS';
    UPDATE archon_settings SET value = 'false' WHERE key = 'USE_RERANKING';
    
    RAISE NOTICE 'Configured for Ollama with 768-dimensional embeddings';
END;
$$ LANGUAGE plpgsql;

-- Function to configure for OpenAI
CREATE OR REPLACE FUNCTION configure_for_openai() RETURNS void AS $$
BEGIN
    -- Update settings for OpenAI
    UPDATE archon_settings SET value = 'openai' WHERE key = 'LLM_PROVIDER';
    UPDATE archon_settings SET value = NULL WHERE key = 'LLM_BASE_URL';
    UPDATE archon_settings SET value = 'text-embedding-3-small' WHERE key = 'EMBEDDING_MODEL';
    UPDATE archon_settings SET value = '1536' WHERE key = 'EMBEDDING_DIMENSIONS';
    UPDATE archon_settings SET value = 'gpt-4o-mini' WHERE key = 'MODEL_CHOICE';
    
    -- Restore default performance settings for OpenAI
    UPDATE archon_settings SET value = '50' WHERE key = 'CRAWL_BATCH_SIZE';
    UPDATE archon_settings SET value = '10' WHERE key = 'CRAWL_MAX_CONCURRENT';
    UPDATE archon_settings SET value = '100' WHERE key = 'DOCUMENT_STORAGE_BATCH_SIZE';
    UPDATE archon_settings SET value = '100' WHERE key = 'EMBEDDING_BATCH_SIZE';
    UPDATE archon_settings SET value = 'true' WHERE key = 'ENABLE_PARALLEL_BATCHES';
    UPDATE archon_settings SET value = '3' WHERE key = 'CONTEXTUAL_EMBEDDINGS_MAX_WORKERS';
    UPDATE archon_settings SET value = '3' WHERE key = 'CODE_SUMMARY_MAX_WORKERS';
    UPDATE archon_settings SET value = '3' WHERE key = 'CODE_EXTRACTION_MAX_WORKERS';
    UPDATE archon_settings SET value = '40' WHERE key = 'CODE_EXTRACTION_BATCH_SIZE';
    UPDATE archon_settings SET value = '50' WHERE key = 'CONTEXTUAL_EMBEDDING_BATCH_SIZE';
    
    RAISE NOTICE 'Configured for OpenAI with 1536-dimensional embeddings';
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- SECTION 14: VERIFICATION
-- =====================================================

DO $$
DECLARE
    source_count INTEGER;
    page_count INTEGER;
    code_count INTEGER;
    settings_count INTEGER;
    provider_setting TEXT;
    dim_setting TEXT;
BEGIN
    -- Count rows in each table
    SELECT COUNT(*) INTO source_count FROM archon_sources;
    SELECT COUNT(*) INTO page_count FROM archon_crawled_pages;
    SELECT COUNT(*) INTO code_count FROM archon_code_examples;
    SELECT COUNT(*) INTO settings_count FROM archon_settings;
    
    -- Get current provider configuration
    SELECT value INTO provider_setting FROM archon_settings WHERE key = 'LLM_PROVIDER';
    SELECT value INTO dim_setting FROM archon_settings WHERE key = 'EMBEDDING_DIMENSIONS';
    
    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║       Archon Unified Database Setup Complete!         ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Database Status:';
    RAISE NOTICE '   ✅ archon_sources: % rows', source_count;
    RAISE NOTICE '   ✅ archon_crawled_pages: % rows', page_count;
    RAISE NOTICE '   ✅ archon_code_examples: % rows', code_count;
    RAISE NOTICE '   ✅ archon_settings: % rows', settings_count;
    RAISE NOTICE '';
    RAISE NOTICE '🔧 Current Configuration:';
    RAISE NOTICE '   Provider: %', provider_setting;
    RAISE NOTICE '   Embedding Dimensions: %', dim_setting;
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Features:';
    RAISE NOTICE '   ✅ Backward compatibility views created';
    RAISE NOTICE '   ✅ Multi-dimensional embedding support';
    RAISE NOTICE '   ✅ Hybrid search enabled';
    RAISE NOTICE '   ✅ Full-text search enabled';
    RAISE NOTICE '   ✅ Projects & Tasks module ready';
    RAISE NOTICE '';
    RAISE NOTICE '💡 Configuration Options:';
    RAISE NOTICE '   • For Ollama: SELECT configure_for_ollama();';
    RAISE NOTICE '   • For OpenAI: SELECT configure_for_openai();';
    RAISE NOTICE '';
    RAISE NOTICE '📝 Next Steps:';
    RAISE NOTICE '   1. Add your API keys via the Settings UI';
    RAISE NOTICE '   2. Choose your provider (OpenAI or Ollama)';
    RAISE NOTICE '   3. Restart Docker services';
    RAISE NOTICE '   4. Start crawling or uploading documents';
    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║     Ready for both OpenAI and Ollama deployments!     ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════════╝';
END $$;

-- =====================================================
-- END OF UNIFIED DATABASE SETUP
-- =====================================================