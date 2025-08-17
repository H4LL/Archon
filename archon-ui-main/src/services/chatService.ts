interface KnowledgeQueryResponse {
  success: boolean;
  answer?: string;
  response?: string;
  sources?: Array<{
    url: string;
    title?: string;
    similarity?: number;
    content?: string;
    metadata?: any;
  }>;
  error?: string;
  total_found?: number;
  isStreaming?: boolean;
}

interface SearchResult {
  id?: string;
  content: string;
  metadata?: {
    url?: string;
    title?: string;
    source?: string;
    [key: string]: any;
  };
  similarity?: number;
  similarity_score?: number;
  url?: string;
}

class ChatService {
  private baseUrl = import.meta.env.VITE_API_URL || 'http://localhost:8181';
  private agentsUrl = import.meta.env.VITE_AGENTS_URL || 'http://localhost:8052';

  async queryKnowledge(query: string, limit: number = 5): Promise<KnowledgeQueryResponse> {
    try {
      // Use the RAG agent for intelligent responses
      const response = await fetch(`${this.agentsUrl}/agents/ollama_rag/stream`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          agent_type: 'ollama_rag',
          prompt: query,
          context: {
            match_count: limit,
          },
        }),
      });

      if (!response.ok) {
        const errorData = await response.text();
        throw new Error(`Agent request failed: ${errorData || response.statusText}`);
      }

      // Handle Server-Sent Events (SSE) stream from the agent
      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      let fullResponse = '';
      let sources: any[] = [];

      if (!reader) {
        throw new Error('Response body is not readable');
      }

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n');

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const eventData = JSON.parse(line.slice(6));
              
              if (eventData.type === 'stream_chunk') {
                fullResponse += eventData.content;
              } else if (eventData.type === 'stream_complete') {
                // Final structured data might contain sources
                if (eventData.content && typeof eventData.content === 'object') {
                  sources = eventData.content.citations || eventData.content.sources || [];
                }
              } else if (eventData.type === 'error') {
                throw new Error(eventData.error);
              }
            } catch (e) {
              console.error('Error parsing SSE event:', e);
            }
          }
        }
      }

      // Format sources from the agent response
      const formattedSources = sources.map((s: any) => ({
        url: s.url || s.source || '#',
        title: s.title || this.extractTitleFromUrl(s.url || s.source || ''),
        similarity: s.relevance || s.similarity || 0,
        content: s.content || s.snippet,
      }));

      return {
        success: true,
        answer: fullResponse || 'No response generated.',
        sources: formattedSources,
        total_found: sources.length,
      };
    } catch (error) {
      console.error('Knowledge query error:', error);
      
      // Check if it's a network error
      if (error instanceof TypeError && error.message.includes('fetch')) {
        return {
          success: false,
          error: 'Unable to connect to the server. Please check if the server is running.',
        };
      }
      
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Query failed',
      };
    }
  }

  private extractTitleFromUrl(url: string): string {
    if (!url) return 'Document';
    
    try {
      // Remove protocol and get pathname
      const urlObj = new URL(url);
      const pathname = urlObj.pathname;
      
      // Get the last segment of the path
      const segments = pathname.split('/').filter(Boolean);
      if (segments.length > 0) {
        const lastSegment = segments[segments.length - 1];
        // Remove file extension and replace dashes/underscores with spaces
        return lastSegment
          .replace(/\.[^/.]+$/, '')
          .replace(/[-_]/g, ' ')
          .replace(/\b\w/g, l => l.toUpperCase());
      }
      
      // Fallback to hostname
      return urlObj.hostname;
    } catch {
      // If URL parsing fails, try to extract something meaningful
      const parts = url.split('/').filter(Boolean);
      return parts[parts.length - 1] || 'Document';
    }
  }

  private generateAnswerFromResults(results: SearchResult[], _query: string): string {
    if (!results || results.length === 0) {
      return "I couldn't find any relevant information in the knowledge base for your query.";
    }

    // Take top 3 most relevant results
    const topResults = results.slice(0, 3);
    
    // Check if results are highly relevant (similarity > 0.7)
    const highlyRelevant = topResults.filter(r => 
      (r.similarity || r.similarity_score || 0) > 0.7
    );

    if (highlyRelevant.length > 0) {
      // Combine content from highly relevant results
      const combinedContent = highlyRelevant
        .map(r => r.content)
        .join('\n\n---\n\n');
      
      // Truncate if too long
      const maxLength = 1000;
      const truncatedContent = combinedContent.length > maxLength 
        ? combinedContent.substring(0, maxLength) + '...'
        : combinedContent;

      return `Based on the knowledge base:\n\n${truncatedContent}\n\nThe above information was found in ${highlyRelevant.length} relevant document${highlyRelevant.length !== 1 ? 's' : ''}.`;
    } else {
      // Results exist but have lower relevance
      const snippet = topResults[0].content.substring(0, 300);
      return `I found some potentially related information, though it may not directly answer your query:\n\n"${snippet}..."\n\nYou may want to refine your search or check the sources for more context.`;
    }
  }

  async queryKnowledgeStream(
    query: string,
    onChunk: (chunk: string) => void,
    onComplete: (data: any) => void,
    limit: number = 5
  ): Promise<void> {
    try {
      // First check if the agent service is reachable
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout
      
      const response = await fetch(`${this.agentsUrl}/agents/ollama_rag/stream`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          agent_type: 'ollama_rag',
          prompt: query,
          context: {
            match_count: limit,
          },
        }),
        signal: controller.signal,
      }).catch(err => {
        clearTimeout(timeoutId);
        if (err.name === 'AbortError') {
          throw new Error('Request timed out. The AI service may be unavailable or responding slowly. Please try again later.');
        }
        throw err;
      });
      
      clearTimeout(timeoutId);

      if (!response.ok) {
        const errorData = await response.text();
        let errorMessage = 'Failed to get a response from the AI service.';
        
        if (response.status === 404) {
          errorMessage = 'The AI agent service is not available. Please ensure all services are running.';
        } else if (response.status === 500) {
          errorMessage = 'The AI service encountered an error. This may be due to missing configuration or resources.';
        } else if (response.status === 503) {
          errorMessage = 'The AI service is temporarily unavailable. Please try again in a moment.';
        } else if (errorData) {
          try {
            const errorJson = JSON.parse(errorData);
            errorMessage = errorJson.detail || errorJson.error || errorMessage;
          } catch {
            errorMessage = errorData || response.statusText;
          }
        }
        
        throw new Error(errorMessage);
      }

      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      let sources: any[] = [];
      let hasReceivedData = false;
      let errorFromStream: string | null = null;

      if (!reader) {
        throw new Error('Unable to read the response from the AI service.');
      }

      // Set a timeout for receiving first data
      const dataTimeout = setTimeout(() => {
        if (!hasReceivedData) {
          errorFromStream = 'The AI service is taking too long to respond. This may indicate the AI model is not running or the knowledge base is empty.';
          reader.cancel();
        }
      }, 30000); // 30 second timeout for first data

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        hasReceivedData = true;
        clearTimeout(dataTimeout);

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n');

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const eventData = JSON.parse(line.slice(6));
              
              if (eventData.type === 'stream_chunk') {
                onChunk(eventData.content);
              } else if (eventData.type === 'stream_complete') {
                // Final structured data with all search results and reasoning
                if (eventData.content && typeof eventData.content === 'object') {
                  const completeData = {
                    sources: (eventData.content.sources || []).map((s: any) => ({
                      url: s.url || s.source || '#',
                      title: s.title || this.extractTitleFromUrl(s.url || s.source || ''),
                      similarity: s.relevance || s.similarity || 0,
                      content: s.content || s.snippet,
                    })),
                    searchResults: eventData.content.search_results || eventData.content.searchResults || [],
                    reasoningSteps: eventData.content.reasoning_steps || eventData.content.reasoningSteps || [],
                    observations: eventData.content.observations || [],
                    totalIterations: eventData.content.total_iterations || eventData.content.totalIterations || 0,
                  };
                  onComplete(completeData);
                } else {
                  // Fallback for basic response
                  onComplete({ sources: [], searchResults: [], reasoningSteps: [], observations: [] });
                }
              } else if (eventData.type === 'error') {
                errorFromStream = this.parseAgentError(eventData.error);
                throw new Error(errorFromStream);
              }
            } catch (e) {
              if (e instanceof Error && e.message) {
                throw e; // Re-throw if it's our error
              }
              console.error('Error parsing SSE event:', e);
            }
          }
        }
      }
      
      if (errorFromStream) {
        throw new Error(errorFromStream);
      }
    } catch (error) {
      console.error('Knowledge query stream error:', error);
      
      // Enhance error messages based on error type
      if (error instanceof TypeError && error.message.includes('fetch')) {
        throw new Error('Unable to connect to the AI service. Please check that all services are running.');
      } else if (error instanceof Error) {
        // Pass through our custom error messages
        throw error;
      } else {
        throw new Error('An unexpected error occurred while querying the knowledge base.');
      }
    }
  }
  
  private parseAgentError(error: string): string {
    // Parse common agent errors and provide user-friendly messages
    if (error.includes('coroutine') || error.includes('async')) {
      return 'The AI service encountered a configuration error. Please contact support.';
    } else if (error.includes('timeout') || error.includes('Timeout')) {
      return 'The request timed out. The AI model may be slow or unavailable.';
    } else if (error.includes('model') || error.includes('ollama')) {
      return 'The AI model is not available. Please ensure Ollama is running and the model is installed.';
    } else if (error.includes('empty') || error.includes('no results')) {
      return 'No relevant information found in the knowledge base. Try adding some documents first.';
    } else if (error.includes('connection') || error.includes('network')) {
      return 'Network connection error. Please check your connection and try again.';
    }
    
    // Return the original error if we can't parse it
    return error;
  }

  async testConnection(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/api/health`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });
      return response.ok;
    } catch {
      return false;
    }
  }
  
  async testAgentConnection(): Promise<{ available: boolean; error?: string }> {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000); // 5 second timeout
      
      const response = await fetch(`${this.agentsUrl}/agents/list`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
        signal: controller.signal,
      });
      
      clearTimeout(timeoutId);
      
      if (!response.ok) {
        return { 
          available: false, 
          error: `Agent service returned ${response.status}: ${response.statusText}` 
        };
      }
      
      const data = await response.json();
      
      // Check if ollama_rag agent is available
      if (data.agents && data.agents.ollama_rag) {
        return { 
          available: data.agents.ollama_rag.available === true,
          error: data.agents.ollama_rag.available ? undefined : 'Ollama RAG agent is not available'
        };
      }
      
      return { 
        available: false, 
        error: 'Ollama RAG agent not found in available agents' 
      };
    } catch (err) {
      if (err instanceof Error) {
        if (err.name === 'AbortError') {
          return { available: false, error: 'Agent service connection timed out' };
        }
        return { available: false, error: `Failed to connect to agent service: ${err.message}` };
      }
      return { available: false, error: 'Unknown error connecting to agent service' };
    }
  }
}

export const chatService = new ChatService();