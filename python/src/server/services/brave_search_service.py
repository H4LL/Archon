"""
Brave Search API integration service for discovering and crawling web content.
"""

import os
from typing import List, Dict, Optional
import httpx
import logging
from pydantic import BaseModel

logger = logging.getLogger(__name__)


class SearchResult(BaseModel):
    """Represents a single search result from Brave Search."""
    url: str
    title: str
    description: str
    favicon: Optional[str] = None
    age: Optional[str] = None


class BraveSearchService:
    """Service for interacting with Brave Search API."""
    
    def __init__(self, api_key: Optional[str] = None):
        """Initialize the Brave Search service.
        
        Args:
            api_key: Brave Search API key. If not provided, will look for BRAVE_SEARCH_API_KEY env var.
        """
        self.api_key = api_key or os.getenv("BRAVE_SEARCH_API_KEY")
        if not self.api_key:
            logger.warning("No Brave Search API key configured. Search functionality will be disabled.")
        else:
            logger.info(f"Brave Search API key loaded: {self.api_key[:10]}...")
        
        self.base_url = "https://api.search.brave.com/res/v1/web/search"
    
    def _get_headers(self):
        """Get headers with current API key - evaluated at request time."""
        return {
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "X-Subscription-Token": self.api_key or os.getenv("BRAVE_SEARCH_API_KEY") or ""
        }
    
    async def search(
        self,
        query: str,
        count: int = 10,
        freshness: Optional[str] = None,
        country: str = "us",
        search_lang: str = "en",
        ui_lang: str = "en-US"
    ) -> List[SearchResult]:
        """Perform a web search using Brave Search API.
        
        Args:
            query: The search query string
            count: Number of results to return (max 20)
            freshness: Time range for results (e.g., 'pd' for past day, 'pw' for past week)
            country: Country code for search localization
            search_lang: Language for search results
            ui_lang: UI language preference
            
        Returns:
            List of SearchResult objects
            
        Raises:
            httpx.HTTPError: If the API request fails
            ValueError: If API key is not configured
        """
        # Check API key at request time
        current_api_key = self.api_key or os.getenv("BRAVE_SEARCH_API_KEY")
        if not current_api_key:
            raise ValueError("Brave Search API key is not configured")
        
        # Limit count to API maximum
        count = min(count, 20)
        
        params = {
            "q": query,
            "count": count,
            "country": country,
            "search_lang": search_lang,
            "ui_lang": ui_lang,
            "safesearch": "moderate",
            "text_decorations": False,
            "spellcheck": True
        }
        
        if freshness:
            params["freshness"] = freshness
        
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                logger.info(f"Searching Brave for: {query} (requesting {count} results)")
                
                # Get headers at request time
                headers = self._get_headers()
                
                response = await client.get(
                    self.base_url,
                    headers=headers,
                    params=params
                )
                response.raise_for_status()
                
                data = response.json()
                
                # Extract web results
                web_results = data.get("web", {}).get("results", [])
                
                # Convert to SearchResult objects
                results = []
                for item in web_results:
                    try:
                        result = SearchResult(
                            url=item["url"],
                            title=item.get("title", ""),
                            description=item.get("description", ""),
                            favicon=item.get("profile", {}).get("img", None),
                            age=item.get("age", None)
                        )
                        results.append(result)
                    except Exception as e:
                        logger.warning(f"Failed to parse search result: {e}")
                        continue
                
                logger.info(f"Brave Search returned {len(results)} results for query: {query}")
                return results
                
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 401:
                logger.error("Invalid Brave Search API key")
                raise ValueError("Invalid Brave Search API key")
            elif e.response.status_code == 422:
                logger.error(f"Brave Search API key error: {e.response.text}")
                raise ValueError(f"Invalid Brave Search API key format. Status: 422. Response: {e.response.text}")
            elif e.response.status_code == 429:
                logger.error("Brave Search API rate limit exceeded")
                raise ValueError("API rate limit exceeded. Please try again later.")
            else:
                logger.error(f"Brave Search API error: {e.response.status_code} - {e.response.text}")
                raise
        except httpx.RequestError as e:
            logger.error(f"Network error calling Brave Search API: {e}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error in Brave Search: {e}")
            raise
    
    async def search_for_crawling(
        self,
        query: str,
        max_results: int = 5,
        freshness: Optional[str] = None
    ) -> Dict:
        """Search and prepare URLs for crawling.
        
        Args:
            query: The search query string
            max_results: Number of results to prepare for crawling (max 20)
            freshness: Time range for results
            
        Returns:
            Dictionary with search term, URLs to crawl, and full results
        """
        results = await self.search(query, count=max_results, freshness=freshness)
        
        return {
            "search_term": query,
            "urls_to_crawl": [r.url for r in results],
            "search_results": [r.model_dump() for r in results],
            "result_count": len(results)
        }
    
    def is_configured(self) -> bool:
        """Check if the Brave Search service is properly configured.
        
        Returns:
            True if API key is configured, False otherwise
        """
        return bool(self.api_key or os.getenv("BRAVE_SEARCH_API_KEY"))


# Singleton instance - will check for env var at request time
brave_search_service = BraveSearchService()
