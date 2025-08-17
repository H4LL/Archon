"""
Ollama ReAct RAG Agent - LangGraph-based agent optimized for Ollama models

This agent uses the ReAct (Reasoning + Acting) pattern with LangGraph to enable
Ollama models to effectively use RAG tools without OpenAI function calling.
"""

import asyncio
import json
import logging
import os
import re
from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict, List, Optional, TypedDict, Annotated, Sequence
import operator

import httpx
from langgraph.graph import StateGraph, END
from pydantic import BaseModel, Field



logger = logging.getLogger(__name__)

# Import credential service for settings access
_credential_service = None

async def get_credential_service():
    """Get or create the credential service instance."""
    global _credential_service
    if _credential_service is None:
        from ..server.services.credential_service import CredentialService
        _credential_service = CredentialService()
        await _credential_service.load_all_credentials()
    return _credential_service


class ActionType(str, Enum):
    """Available actions for the agent."""
    SEARCH_DOCUMENTS = "search_documents"
    LIST_SOURCES = "list_sources"
    SEARCH_CODE = "search_code"
    RESPOND = "respond"
    THINK = "think"


class AgentState(TypedDict):
    """State that flows through the LangGraph."""
    query: str
    messages: Annotated[Sequence[str], operator.add]
    current_thought: Optional[str]
    current_action: Optional[str]
    current_action_input: Optional[Dict[str, Any]]
    observations: Annotated[List[Dict[str, Any]], operator.add]
    final_answer: Optional[str]
    iteration_count: int
    max_iterations: int
    should_continue: bool
    no_results_count: int  # Track consecutive no-result searches


@dataclass
class OllamaRagDependencies:
    """Dependencies for Ollama RAG operations."""
    project_id: str | None = None
    source_filter: str | None = None
    match_count: int = 5
    max_iterations: int = 3
    temperature: float = 0.7
    progress_callback: Any | None = None


class ReActResponse(BaseModel):
    """Structured output for ReAct agent responses."""
    success: bool = Field(description="Whether the query was successful")
    answer: str = Field(description="The final answer to the user's query")
    reasoning_steps: List[Dict[str, Any]] = Field(description="Steps taken to arrive at answer")
    sources_used: List[str] = Field(description="Sources referenced in the answer")
    total_iterations: int = Field(description="Number of reasoning iterations")
    search_results: List[Dict[str, Any]] = Field(description="All search results found", default_factory=list)
    observations: List[Dict[str, Any]] = Field(description="All observations from the search", default_factory=list)


class OllamaReActRagAgent:
    """
    ReAct-based RAG agent optimized for Ollama models.
    
    Uses LangGraph to implement a Reasoning + Acting loop that allows
    Ollama models to effectively search and retrieve information without
    requiring OpenAI-style function calling.
    """
    
    def __init__(self, model: str = None, **kwargs):
        # Store the provided model, will fetch from settings if None
        self._provided_model = model
        self.ollama_model = None  # Will be set asynchronously
        
        # Initialize the graph
        self.workflow = None
        self.compiled_graph = None
        
        # Initialize HTTP client for API calls
        api_port = os.getenv("ARCHON_SERVER_PORT", "8181")
        if os.getenv("DOCKER_CONTAINER"):
            self.api_url = f"http://archon-server:{api_port}"
        else:
            self.api_url = f"http://localhost:{api_port}"
        self.http_client = None  # Will be created when needed
        
        # Store the model to use - will be fetched from settings if not provided
        self.model = model  # Will be set from MODEL_CHOICE if None
        self.name = "OllamaReActRagAgent"
        
        # Initialize the LangGraph workflow
        self._create_workflow()
        
    def _create_workflow(self):
        """Create the LangGraph workflow."""
        # Build the state graph
        self.workflow = StateGraph(AgentState)
        
        # Add nodes
        self.workflow.add_node("reason", self._reason_node)
        self.workflow.add_node("act", self._act_node) 
        self.workflow.add_node("observe", self._observe_node)
        self.workflow.add_node("decide", self._decide_node)
        self.workflow.add_node("respond", self._respond_node)
        
        # Set entry point
        self.workflow.set_entry_point("reason")
        
        # Add edges
        self.workflow.add_edge("reason", "act")
        self.workflow.add_edge("act", "observe")
        self.workflow.add_edge("observe", "decide")
        
        # Conditional routing from decide node
        self.workflow.add_conditional_edges(
            "decide",
            self._should_continue,
            {
                "continue": "reason",
                "respond": "respond",
                "end": END
            }
        )
        
        self.workflow.add_edge("respond", END)
        
        # Compile the graph
        self.compiled_graph = self.workflow.compile()
    
    def get_system_prompt(self) -> str:
        """Get the ReAct system prompt optimized for Ollama."""
        return """You are a ReAct (Reasoning and Acting) agent with access to a knowledge base.

You MUST follow this EXACT pattern for every response:

Thought: [Your reasoning about what to do next]
Action: [One of: search_documents, list_sources, search_code, respond]
Action Input: [JSON object with parameters]

Available actions:
- search_documents: Search the knowledge base
  Input: {"query": "search terms"}
- list_sources: List available documentation sources
  Input: {}
- search_code: Find code examples
  Input: {"query": "code search terms"}
- respond: Provide final answer
  Input: {"answer": "your response"}

IMPORTANT RULES:
1. ALWAYS start with "Thought:" 
2. ALWAYS follow with "Action:" on the next line
3. ALWAYS follow with "Action Input:" on the next line
4. Use proper JSON for Action Input
5. Wait for observation before next thought
6. If you get no results after 2 searches, provide the best answer you can
7. Don't repeat the same search with identical terms

Example:
User: Tell me about FastAPI

Thought: I need to search for information about FastAPI in the knowledge base
Action: search_documents
Action Input: {"query": "FastAPI framework Python"}

[You will receive an observation]

Thought: I found good information. Let me also look for code examples
Action: search_code  
Action Input: {"query": "FastAPI example"}

[You will receive an observation]

Thought: Now I have comprehensive information to answer the user
Action: respond
Action Input: {"answer": "FastAPI is a modern web framework..."}"""

    async def _reason_node(self, state: AgentState) -> AgentState:
        """Reasoning step - decide what action to take."""
        try:
            # Check if we've had too many empty results
            no_results = state.get('no_results_count', 0)
            if no_results >= 2:
                logger.info("Too many empty results, forcing response")
                state['current_thought'] = "I've searched multiple times but found no relevant information in the knowledge base."
                state['current_action'] = ActionType.RESPOND
                state['current_action_input'] = {
                    "answer": f"I couldn't find any information about '{state['query']}' in the current knowledge base. The knowledge base may not contain information on this topic, or it may need to be populated with relevant documents first."
                }
                return state
            
            # Build context from observations
            context = self._build_context(state)
            
            # Create reasoning prompt
            prompt = f"""Current task: {state['query']}

Previous observations:
{context}

What should I do next? Follow the Thought/Action/Action Input pattern.
Remember: If you've already searched and found no results, try a different search or provide the best answer you can."""

            # Get LLM response
            response = await self._get_llm_response(prompt)
            
            # Parse the response
            thought, action, action_input = self._parse_react_response(response)
            
            # Update state
            state['current_thought'] = thought
            state['current_action'] = action
            state['current_action_input'] = action_input
            state['messages'] = state.get('messages', []) + [f"Thought: {thought}"]
            
            logger.info(f"Reasoning: {thought}")
            logger.debug(f"Action chosen: {action} with input: {action_input}")
            
        except Exception as e:
            logger.error(f"Error in reason node: {e}")
            state['current_action'] = ActionType.RESPOND
            state['current_action_input'] = {"answer": "I encountered an error while processing your request."}
            
        return state

    async def _act_node(self, state: AgentState) -> AgentState:
        """Execute the chosen action."""
        action = state.get('current_action', ActionType.RESPOND)
        action_input = state.get('current_action_input', {})
        
        try:
            result = None
            
            if action == ActionType.SEARCH_DOCUMENTS:
                result = await self._search_documents(action_input)
            elif action == ActionType.LIST_SOURCES:
                result = await self._list_sources()
            elif action == ActionType.SEARCH_CODE:
                result = await self._search_code_examples(action_input)
            elif action == ActionType.RESPOND:
                # Final response action
                state['final_answer'] = action_input.get('answer', '')
                state['should_continue'] = False
                return state
            else:
                result = {"error": f"Unknown action: {action}"}
            
            # Check if we got empty results
            has_results = False
            if isinstance(result, dict):
                if 'results' in result and len(result.get('results', [])) > 0:
                    has_results = True
                elif 'sources' in result and len(result.get('sources', [])) > 0:
                    has_results = True
                elif 'error' not in result and result:  # Non-empty dict without error
                    has_results = True
            
            # Update no_results_count
            if not has_results and action in [ActionType.SEARCH_DOCUMENTS, ActionType.SEARCH_CODE]:
                state['no_results_count'] = state.get('no_results_count', 0) + 1
                logger.info(f"No results found, count: {state['no_results_count']}")
            elif has_results:
                state['no_results_count'] = 0  # Reset counter on successful search
            
            # Store the observation
            state['observations'] = state.get('observations', []) + [{
                'action': action,
                'input': action_input,
                'result': result,
                'has_results': has_results
            }]
            
            state['messages'] = state.get('messages', []) + [
                f"Action: {action}",
                f"Observation: {json.dumps(result, indent=2)[:500] if result else 'No results found'}"
            ]
            
        except Exception as e:
            logger.error(f"Error in act node: {e}")
            state['observations'] = state.get('observations', []) + [{
                'action': action,
                'error': str(e)
            }]
            state['no_results_count'] = state.get('no_results_count', 0) + 1
            
        return state

    async def _observe_node(self, state: AgentState) -> AgentState:
        """Process observations and update iteration count."""
        state['iteration_count'] = state.get('iteration_count', 0) + 1
        
        # Log the observation
        if state.get('observations'):
            last_obs = state['observations'][-1]
            if 'error' in last_obs:
                logger.warning(f"Error in last observation: {last_obs['error']}")
            else:
                result_count = 0
                if 'result' in last_obs and isinstance(last_obs['result'], dict):
                    if 'results' in last_obs['result']:
                        result_count = len(last_obs['result']['results'])
                    elif 'sources' in last_obs['result']:
                        result_count = len(last_obs['result']['sources'])
                logger.info(f"Observation from {last_obs.get('action')}: {result_count} results")
        
        return state

    async def _decide_node(self, state: AgentState) -> AgentState:
        """Decide whether to continue iterating or provide final answer."""
        # Check if we should stop
        if state.get('should_continue') is False:
            return state
            
        # Check if we've had too many no-result searches
        if state.get('no_results_count', 0) >= 2:
            logger.info("Too many searches with no results, forcing response")
            state['should_continue'] = False
            return state
            
        # Check iteration limit
        if state['iteration_count'] >= state.get('max_iterations', 3):
            logger.info("Reached max iterations, generating final response")
            state['should_continue'] = False
            return state
        
        # Check if last action was respond
        if state.get('current_action') == ActionType.RESPOND:
            state['should_continue'] = False
            return state
            
        # Continue by default
        state['should_continue'] = True
        return state

    def _should_continue(self, state: AgentState) -> str:
        """Determine next step in the graph."""
        if state.get('should_continue', True) and state.get('current_action') != ActionType.RESPOND:
            return "continue"
        elif state.get('final_answer'):
            return "end"
        else:
            return "respond"

    async def _respond_node(self, state: AgentState) -> AgentState:
        """Generate final response based on all observations."""
        if state.get('final_answer'):
            # Already have a final answer from respond action
            return state
            
        try:
            # Check if we have any successful results
            has_any_results = any(
                obs.get('has_results', False) 
                for obs in state.get('observations', [])
            )
            
            if not has_any_results:
                # No results found at all
                state['final_answer'] = (
                    f"I couldn't find any information about '{state['query']}' in the knowledge base. "
                    "The knowledge base may not contain information on this topic. "
                    "Please ensure relevant documents have been uploaded or crawled first."
                )
            else:
                # Build comprehensive context
                context = self._build_full_context(state)
                
                # Create synthesis prompt
                prompt = f"""Original question: {state['query']}

Information gathered:
{context}

Based on all this information, provide a comprehensive, natural answer to the user's question.
Be helpful and cite specific information from the search results.
If no relevant information was found, say so clearly."""

                # Get final response
                response = await self._get_llm_response(prompt)
                state['final_answer'] = response
            
        except Exception as e:
            logger.error(f"Error generating final response: {e}")
            state['final_answer'] = "I encountered an error while generating the response."
            
        return state

    def _parse_react_response(self, response: str) -> tuple[str, str, dict]:
        """Parse ReAct format response into components."""
        thought = ""
        action = ActionType.RESPOND
        action_input = {}
        
        try:
            # Extract thought
            thought_match = re.search(r'Thought:\s*(.+?)(?=Action:|$)', response, re.DOTALL | re.IGNORECASE)
            if thought_match:
                thought = thought_match.group(1).strip()
            
            # Extract action
            action_match = re.search(r'Action:\s*(\w+)', response, re.IGNORECASE)
            if action_match:
                action_str = action_match.group(1).lower()
                # Map to ActionType
                if 'search_doc' in action_str:
                    action = ActionType.SEARCH_DOCUMENTS
                elif 'list' in action_str:
                    action = ActionType.LIST_SOURCES
                elif 'search_code' in action_str or 'code' in action_str:
                    action = ActionType.SEARCH_CODE
                elif 'respond' in action_str or 'answer' in action_str:
                    action = ActionType.RESPOND
                else:
                    action = ActionType.SEARCH_DOCUMENTS  # Default
            
            # Extract action input
            input_match = re.search(r'Action Input:\s*({.+?}|\[.+?\])', response, re.DOTALL | re.IGNORECASE)
            if input_match:
                try:
                    action_input = json.loads(input_match.group(1))
                except json.JSONDecodeError:
                    # Try to extract key-value pairs manually
                    query_match = re.search(r'"query":\s*"([^"]+)"', input_match.group(1))
                    if query_match:
                        action_input = {"query": query_match.group(1)}
                    answer_match = re.search(r'"answer":\s*"([^"]+)"', input_match.group(1))
                    if answer_match:
                        action_input = {"answer": answer_match.group(1)}
            
            # Fallback for respond action without proper format
            if action == ActionType.RESPOND and not action_input:
                # Try to extract answer from thought or use full response
                action_input = {"answer": thought if thought else response}
                
        except Exception as e:
            logger.warning(f"Error parsing ReAct response: {e}")
            # Default to respond with the full response
            thought = "Processing response"
            action = ActionType.RESPOND
            action_input = {"answer": response}
        
        return thought, action, action_input

    def _build_context(self, state: AgentState) -> str:
        """Build context from previous observations."""
        if not state.get('observations'):
            return "No observations yet."
        
        context_parts = []
        for obs in state['observations'][-3:]:  # Last 3 observations
            action = obs.get('action', 'unknown')
            result = obs.get('result', {})
            has_results = obs.get('has_results', False)
            
            if 'error' in obs:
                context_parts.append(f"- {action} failed: {obs['error']}")
            elif has_results:
                if isinstance(result, dict):
                    if 'results' in result:
                        count = len(result['results'])
                        context_parts.append(f"- {action} returned {count} results")
                    elif 'sources' in result:
                        count = len(result['sources'])
                        context_parts.append(f"- {action} found {count} sources")
                    else:
                        context_parts.append(f"- {action} completed successfully")
            else:
                context_parts.append(f"- {action} returned no results")
        
        return "\n".join(context_parts)

    async def _get_http_client(self):
        """Get or create HTTP client."""
        if self.http_client is None:
            self.http_client = httpx.AsyncClient(timeout=30.0)
        return self.http_client
    
    async def _cleanup_http_client(self):
        """Clean up HTTP client if it exists."""
        if self.http_client is not None:
            await self.http_client.aclose()
            self.http_client = None

    def _build_full_context(self, state: AgentState) -> str:
        """Build full context for final response generation."""
        context_parts = []
        
        for obs in state.get('observations', []):
            action = obs.get('action', 'unknown')
            result = obs.get('result', {})
            has_results = obs.get('has_results', False)
            
            if 'error' in obs:
                context_parts.append(f"Error from {action}: {obs['error']}")
                continue
            
            if not has_results:
                context_parts.append(f"No results found for {action}")
                continue
                
            if action == ActionType.SEARCH_DOCUMENTS and 'results' in result:
                context_parts.append(f"\nDocument search results:")
                # Include ALL results for comprehensive response
                for i, doc in enumerate(result['results'], 1):
                    content = doc.get('content', '')[:500]  # Increased from 200 to 500
                    url = doc.get('url', doc.get('metadata', {}).get('url', ''))
                    source = doc.get('source', doc.get('metadata', {}).get('source_id', ''))
                    similarity = doc.get('similarity', 0)
                    
                    context_parts.append(f"{i}. [Relevance: {similarity:.2f}] {content}...")
                    if url:
                        context_parts.append(f"   Source: {url}")
                    elif source:
                        context_parts.append(f"   Source ID: {source}")
                    
            elif action == ActionType.LIST_SOURCES and 'sources' in result:
                context_parts.append(f"\nAvailable sources:")
                for source in result['sources']:  # Include all sources
                    context_parts.append(f"- {source.get('title', source.get('source_id', 'Unknown'))}")
                    
            elif action == ActionType.SEARCH_CODE and 'results' in result:
                context_parts.append(f"\nCode examples found:")
                for i, example in enumerate(result['results'], 1):  # Include all code examples
                    context_parts.append(f"{i}. {example.get('summary', 'Code example')}")
                    if 'code' in example:
                        context_parts.append(f"   Code snippet: {example['code'][:200]}...")
        
        return "\n".join(context_parts) if context_parts else "No information was found in the knowledge base."

    async def _search_documents(self, params: dict) -> dict:
        """Execute document search directly using Supabase."""
        try:
            query = params.get('query', '')
            logger.info(f"Searching for: {query}")
            
            # Import Supabase client
            from supabase import create_client, Client
            
            # Get Supabase credentials from environment
            supabase_url = os.getenv("SUPABASE_URL")
            supabase_key = os.getenv("SUPABASE_SERVICE_KEY")
            
            if not supabase_url or not supabase_key:
                logger.error("Supabase credentials not found")
                return {"error": "Database configuration missing", "results": []}
            
            # Create Supabase client
            supabase: Client = create_client(supabase_url, supabase_key)
            
            # Create embedding directly using Ollama
            # Since we can't import from server, we'll create the embedding directly
            ollama_url = os.getenv("OLLAMA_BASE_URL", "http://host.docker.internal:11434")
            
            # Create embedding using Ollama's nomic-embed-text model
            async with httpx.AsyncClient(timeout=30.0) as embedding_client:
                embed_response = await embedding_client.post(
                    f"{ollama_url}/api/embeddings",
                    json={
                        "model": "nomic-embed-text",
                        "prompt": query
                    }
                )
                
                if embed_response.status_code != 200:
                    logger.error(f"Failed to create embedding: {embed_response.text}")
                    return {"error": "Failed to create query embedding", "results": []}
                
                embed_data = embed_response.json()
                query_embedding = embed_data.get("embedding", [])
            
            if not query_embedding:
                logger.error("Failed to create embedding for query")
                return {"error": "Failed to create query embedding", "results": []}
            
            # Perform vector similarity search directly on documents table
            response = supabase.rpc(
                'match_archon_crawled_pages',
                {
                    'query_embedding': query_embedding,
                    'match_count': params.get('match_count', 5),
                    'filter': {},  # No filter for now
                    'source_filter': params.get('source_filter', None)
                }
            ).execute()
            
            if response.data:
                # Format results
                results = []
                for doc in response.data[:5]:  # Limit to 5 results
                    results.append({
                        'content': doc.get('content', ''),
                        'metadata': doc.get('metadata', {}),
                        'similarity': doc.get('similarity', 0),
                        'url': doc.get('metadata', {}).get('url', ''),
                        'source': doc.get('metadata', {}).get('source_id', '')
                    })
                
                logger.info(f"Found {len(results)} results for query: {query}")
                return {
                    "success": True,
                    "results": results,
                    "total_found": len(results)
                }
            else:
                logger.info(f"No results found for query: {query}")
                return {
                    "success": True,
                    "results": [],
                    "total_found": 0
                }
            
        except Exception as e:
            logger.error(f"Document search error: {e}", exc_info=True)
            return {"error": str(e), "results": []}

    async def _list_sources(self) -> dict:
        """List available sources via direct API call."""
        try:
            client = await self._get_http_client()
            
            response = await client.get(f"{self.api_url}/api/rag/sources")
            response.raise_for_status()
            result = response.json()
            
            # Format the response correctly
            if isinstance(result, list):
                return {"sources": result}
            elif isinstance(result, dict):
                if 'sources' in result:
                    return result
                elif 'data' in result:
                    # Handle wrapped response
                    data = result['data']
                    if isinstance(data, list):
                        return {"sources": data}
                    elif isinstance(data, dict) and 'sources' in data:
                        return data
                    else:
                        return {"sources": []}
                else:
                    # Assume the dict itself is a source
                    return {"sources": [result]}
            else:
                return {"sources": []}
            
        except Exception as e:
            logger.error(f"List sources error: {e}")
            return {"error": str(e), "sources": []}

    async def _search_code_examples(self, params: dict) -> dict:
        """Execute code examples search - return empty for now to avoid circular dependency."""
        try:
            query = params.get('query', '')
            logger.info(f"Would search code for: {query}")
            
            # For now, return empty results to avoid the circular dependency
            return {
                "success": True,
                "results": [],
                "reranked": False,
                "message": "Code search is currently unavailable."
            }
            
        except Exception as e:
            logger.error(f"Code search error: {e}")
            return {"error": str(e), "results": []}



    async def _get_model_choice(self) -> str:
        """Get the MODEL_CHOICE from settings or use default."""
        try:
            # Try to get from API endpoint
            client = await self._get_http_client()
            response = await client.get(f"{self.api_url}/api/settings/credentials")
            if response.status_code == 200:
                settings = response.json()
                model = settings.get("MODEL_CHOICE", "qwen3:0.6b")
                logger.info(f"Using MODEL_CHOICE from settings: {model}")
                return model
        except Exception as e:
            logger.warning(f"Failed to get MODEL_CHOICE from API: {e}")
        
        # Fallback to environment or default
        model = os.getenv("MODEL_CHOICE", "qwen3:0.6b")
        logger.info(f"Using MODEL_CHOICE from env/default: {model}")
        return model

    async def _get_llm_response(self, prompt: str) -> str:
        """Get response from Ollama model directly."""
        try:
            # Get Ollama base URL
            ollama_url = os.getenv("OLLAMA_BASE_URL", "http://host.docker.internal:11434")
            
            # Get the model to use
            if not self.model:
                self.model = await self._get_model_choice()
            
            # Prepare the request to Ollama
            payload = {
                "model": self.model,  # Use MODEL_CHOICE or provided model
                "prompt": prompt,
                "stream": False,
                "system": self.get_system_prompt()
            }
            
            # Call Ollama API directly
            client = await self._get_http_client()
            response = await client.post(
                f"{ollama_url}/api/generate",
                json=payload,
                timeout=httpx.Timeout(60.0)
            )
            
            if response.status_code == 200:
                result = response.json()
                return result.get("response", "")
            else:
                logger.error(f"Ollama API error: {response.status_code} - {response.text}")
                return ""
                
        except Exception as e:
            logger.error(f"LLM response error: {e}")
            return ""

    async def run_react(self, query: str, deps: OllamaRagDependencies | Any) -> ReActResponse:
        """Execute the ReAct loop for a query."""
        try:
            
            # Handle deps being passed as dict from server
            max_iterations = 3  # default
            if isinstance(deps, dict):
                max_iterations = deps.get('max_iterations', 3)
            elif hasattr(deps, 'max_iterations'):
                max_iterations = deps.max_iterations
            
            # Initialize state
            initial_state: AgentState = {
                'query': query,
                'messages': [],
                'current_thought': None,
                'current_action': None,
                'current_action_input': None,
                'observations': [],
                'final_answer': None,
                'iteration_count': 0,
                'max_iterations': max_iterations,
                'should_continue': True,
                'no_results_count': 0  # Initialize the counter
            }
            
            # Run the graph
            final_state = await self.compiled_graph.ainvoke(initial_state)
            
            # Extract sources and all search results
            sources_used = []
            all_search_results = []
            
            for obs in final_state.get('observations', []):
                if obs.get('has_results') and 'result' in obs and 'results' in obs['result']:
                    for result in obs['result']['results']:
                        # Add to search results
                        search_result = {
                            'content': result.get('content', ''),
                            'url': result.get('url', result.get('metadata', {}).get('url', '')),
                            'source': result.get('source', result.get('metadata', {}).get('source_id', '')),
                            'similarity': result.get('similarity', 0),
                            'metadata': result.get('metadata', {})
                        }
                        all_search_results.append(search_result)
                        
                        # Track unique sources
                        if 'url' in result:
                            sources_used.append(result['url'])
                        elif 'metadata' in result and 'url' in result['metadata']:
                            sources_used.append(result['metadata']['url'])
            
            # Build comprehensive reasoning steps with full detail
            reasoning_steps = []
            thought_count = 0
            
            for obs in final_state.get('observations', []):
                thought_count += 1
                step = {
                    'step': thought_count,
                    'action': obs.get('action', 'unknown'),
                    'action_input': obs.get('input', {}),
                    'has_results': obs.get('has_results', False)
                }
                
                if 'error' in obs:
                    step['error'] = obs['error']
                elif obs.get('has_results') and 'result' in obs:
                    result = obs['result']
                    if 'results' in result:
                        step['result_count'] = len(result['results'])
                        step['results_preview'] = [
                            {
                                'content': r.get('content', '')[:200],
                                'similarity': r.get('similarity', 0),
                                'url': r.get('url', r.get('metadata', {}).get('url', ''))
                            }
                            for r in result['results'][:3]  # Preview of top 3
                        ]
                    elif 'sources' in result:
                        step['sources_count'] = len(result['sources'])
                        
                reasoning_steps.append(step)
            
            # Create formatted observations for display
            formatted_observations = []
            for obs in final_state.get('observations', []):
                formatted_obs = {
                    'action': obs.get('action', 'unknown'),
                    'query': obs.get('input', {}).get('query', '') if obs.get('input') else '',
                    'has_results': obs.get('has_results', False)
                }
                
                if obs.get('has_results') and 'result' in obs and 'results' in obs['result']:
                    formatted_obs['results'] = obs['result']['results']
                    
                formatted_observations.append(formatted_obs)
            
            return ReActResponse(
                success=bool(final_state.get('final_answer')),
                answer=final_state.get('final_answer', 'Unable to generate response'),
                reasoning_steps=reasoning_steps,
                sources_used=list(set(sources_used)),  # Deduplicate
                total_iterations=final_state.get('iteration_count', 0),
                search_results=all_search_results,
                observations=formatted_observations
            )
            
        except Exception as e:
            logger.error(f"ReAct execution error: {e}")
            return ReActResponse(
                success=False,
                answer=f"Error: {str(e)}",
                reasoning_steps=[],
                sources_used=[],
                total_iterations=0
            )

    # Override base agent's run method to use ReAct
    async def run(self, user_prompt: str, deps: OllamaRagDependencies | dict) -> str:
        """Run the agent with ReAct loop."""
        # Convert dict to OllamaRagDependencies if needed
        if isinstance(deps, dict):
            from dataclasses import dataclass
            @dataclass
            class DepsWrapper:
                source_filter: str | None
                match_count: int
                max_iterations: int
            
            deps_obj = DepsWrapper(
                source_filter=deps.get("source_filter"),
                match_count=deps.get("match_count", 5),
                max_iterations=deps.get("max_iterations", 3)
            )
            result = await self.run_react(user_prompt, deps_obj)
        else:
            result = await self.run_react(user_prompt, deps)
        return result.answer
    
    # Override run_stream to avoid using PydanticAI's OpenAI client
    def run_stream(self, user_prompt: str, deps: OllamaRagDependencies):
        """Custom streaming implementation that bypasses PydanticAI."""
        import asyncio
        from typing import AsyncIterator
        
        class OllamaStreamContext:
            """Mock stream context for compatibility."""
            def __init__(self, agent, prompt, deps):
                self.agent = agent
                self.prompt = prompt
                self.deps = deps
                self.result = None
                
            async def __aenter__(self):
                return self
                
            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass
                
            async def stream_text(self) -> AsyncIterator[str]:
                """Stream the response in chunks."""
                # Run the ReAct loop
                self.result = await self.agent.run_react(self.prompt, self.deps)
                
                # Stream the answer in chunks
                answer = self.result.answer
                chunk_size = 50  # Characters per chunk
                
                for i in range(0, len(answer), chunk_size):
                    chunk = answer[i:i + chunk_size]
                    yield chunk
                    await asyncio.sleep(0.01)  # Small delay for streaming effect
                    
            async def get_data(self):
                """Return the full result including sources and search results."""
                if self.result:
                    return {
                        'answer': self.result.answer,
                        'sources': [
                            {
                                'url': url,
                                'title': url.split('/')[-1] if '/' in url else url
                            }
                            for url in self.result.sources_used
                        ],
                        'search_results': self.result.search_results,
                        'reasoning_steps': self.result.reasoning_steps,
                        'observations': self.result.observations,
                        'total_iterations': self.result.total_iterations
                    }
                return {'answer': '', 'sources': [], 'search_results': [], 'reasoning_steps': [], 'observations': []}
        
        return OllamaStreamContext(self, user_prompt, deps)


# Export for use in server
__all__ = ['OllamaReActRagAgent', 'OllamaRagDependencies', 'ReActResponse']
