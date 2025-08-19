"""
Test suite for Brave Search and Crawl functionality.
Tests the complete flow from search to crawling with progress updates.
"""

import asyncio
import pytest
from unittest.mock import Mock, AsyncMock, patch, MagicMock, call
from typing import List, Dict, Any
import json
from datetime import datetime

# Import the modules we're testing
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))


class TestBraveSearchService:
    """Test the Brave search service functionality."""
    
    @pytest.fixture
    def brave_service(self):
        """Create a Brave search service instance."""
        from src.server.services.brave_search_service import BraveSearchService
        return BraveSearchService(api_key="test_api_key")
    
    @pytest.mark.asyncio
    async def test_search_with_valid_api_key(self, brave_service):
        """Test search with valid API key."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_response = Mock()
            mock_response.status_code = 200
            mock_response.json.return_value = {
                "web": {
                    "results": [
                        {
                            "url": "https://example.com/1",
                            "title": "Example 1",
                            "description": "First example",
                            "profile": {"img": "https://example.com/favicon.ico"},
                            "age": "2 days ago"
                        },
                        {
                            "url": "https://example.com/2",
                            "title": "Example 2",
                            "description": "Second example"
                        }
                    ]
                }
            }
            mock_response.raise_for_status = Mock()
            
            mock_client.return_value.__aenter__.return_value.get = AsyncMock(return_value=mock_response)
            
            results = await brave_service.search("test query", count=2)
            
            assert len(results) == 2
            assert results[0].url == "https://example.com/1"
            assert results[0].title == "Example 1"
            assert results[1].url == "https://example.com/2"
    
    @pytest.mark.asyncio
    async def test_search_without_api_key(self):
        """Test that search fails without API key."""
        from src.server.services.brave_search_service import BraveSearchService
        
        service = BraveSearchService(api_key=None)
        
        with pytest.raises(ValueError, match="Brave Search API key is not configured"):
            await service.search("test query")
    
    @pytest.mark.asyncio
    async def test_search_for_crawling(self, brave_service):
        """Test search_for_crawling method."""
        with patch.object(brave_service, 'search') as mock_search:
            mock_search.return_value = [
                Mock(url="https://example.com/1", title="Page 1", description="Desc 1", model_dump=lambda: {"url": "https://example.com/1", "title": "Page 1"}),
                Mock(url="https://example.com/2", title="Page 2", description="Desc 2", model_dump=lambda: {"url": "https://example.com/2", "title": "Page 2"})
            ]
            
            result = await brave_service.search_for_crawling("test query", max_results=2)
            
            assert result["search_term"] == "test query"
            assert len(result["urls_to_crawl"]) == 2
            assert result["urls_to_crawl"][0] == "https://example.com/1"
            assert result["result_count"] == 2


class TestSearchAndCrawlEndpoint:
    """Test the search and crawl API endpoint."""
    
    @pytest.fixture
    def mock_dependencies(self):
        """Mock all dependencies for the endpoint."""
        with patch('src.server.api_routes.knowledge_api.brave_search_service') as mock_brave, \
             patch('src.server.api_routes.knowledge_api.get_crawler') as mock_crawler, \
             patch('src.server.api_routes.knowledge_api.get_supabase_client') as mock_supabase, \
             patch('src.server.api_routes.knowledge_api.CrawlOrchestrationService') as mock_crawl_service, \
             patch('src.server.api_routes.knowledge_api.start_crawl_progress') as mock_start, \
             patch('src.server.api_routes.knowledge_api.update_crawl_progress') as mock_update, \
             patch('src.server.api_routes.knowledge_api.complete_crawl_progress') as mock_complete:
            
            # Configure mocks
            mock_brave.is_configured.return_value = True
            mock_brave.search_for_crawling = AsyncMock(return_value={
                "search_term": "test query",
                "urls_to_crawl": ["https://example.com/1", "https://example.com/2"],
                "search_results": [
                    {"url": "https://example.com/1", "title": "Page 1", "description": "Desc 1"},
                    {"url": "https://example.com/2", "title": "Page 2", "description": "Desc 2"}
                ],
                "result_count": 2
            })
            
            mock_crawler.return_value = AsyncMock()
            mock_supabase.return_value = Mock()
            
            mock_crawl_instance = Mock()
            mock_crawl_instance.set_progress_id = Mock()
            mock_crawl_service.return_value = mock_crawl_instance
            
            mock_start.return_value = AsyncMock()
            mock_update.return_value = AsyncMock()
            mock_complete.return_value = AsyncMock()
            
            yield {
                'brave': mock_brave,
                'crawler': mock_crawler,
                'supabase': mock_supabase,
                'crawl_service': mock_crawl_service,
                'crawl_instance': mock_crawl_instance,
                'start_progress': mock_start,
                'update_progress': mock_update,
                'complete_progress': mock_complete
            }
    
    @pytest.mark.asyncio
    async def test_search_and_crawl_success(self, mock_dependencies):
        """Test successful search and crawl operation."""
        from src.server.api_routes.knowledge_api import search_and_crawl
        from fastapi import BackgroundTasks
        
        # Create mock request
        mock_request = Mock()
        mock_request.json = AsyncMock(return_value={
            "search_term": "test query",
            "max_results": 2,
            "knowledge_type": "technical",
            "tags": ["test", "search"],
            "crawl_depth": 1
        })
        
        background_tasks = BackgroundTasks()
        
        # Execute
        result = await search_and_crawl(
            request=mock_request,
            background_tasks=background_tasks,
            search_term="test query",
            max_results=2,
            knowledge_type="technical",
            tags=["test", "search"],
            crawl_depth=1,
            freshness=None
        )
        
        # Verify search was performed
        assert mock_dependencies['brave'].search_for_crawling.called
        call_args = mock_dependencies['brave'].search_for_crawling.call_args
        assert call_args[1]['query'] == "test query"
        assert call_args[1]['max_results'] == 2
        
        # Verify result structure
        assert result['success'] == True
        assert result['search_term'] == "test query"
        assert len(result['urls_found']) == 2
        assert result['crawl_progress_id'].startswith('search_')
        assert result['total_results'] == 2
    
    @pytest.mark.asyncio
    async def test_search_no_brave_api_key(self, mock_dependencies):
        """Test that search fails when Brave API is not configured."""
        from src.server.api_routes.knowledge_api import search_and_crawl
        from fastapi import HTTPException, BackgroundTasks
        
        mock_dependencies['brave'].is_configured.return_value = False
        
        mock_request = Mock()
        background_tasks = BackgroundTasks()
        
        with pytest.raises(HTTPException) as exc_info:
            await search_and_crawl(
                request=mock_request,
                background_tasks=background_tasks,
                search_term="test query",
                max_results=2
            )
        
        assert exc_info.value.status_code == 503
        assert "Brave Search API is not configured" in str(exc_info.value.detail)
    
    @pytest.mark.asyncio
    async def test_search_no_results(self, mock_dependencies):
        """Test handling when search returns no results."""
        from src.server.api_routes.knowledge_api import search_and_crawl
        from fastapi import BackgroundTasks
        
        mock_dependencies['brave'].search_for_crawling.return_value = {
            "search_term": "obscure query",
            "urls_to_crawl": [],
            "search_results": [],
            "result_count": 0
        }
        
        mock_request = Mock()
        background_tasks = BackgroundTasks()
        
        result = await search_and_crawl(
            request=mock_request,
            background_tasks=background_tasks,
            search_term="obscure query",
            max_results=5
        )
        
        assert result['success'] == False
        assert result['message'] == "No search results found"
        assert result['crawl_progress_id'] is None


class TestCrawlSearchResultsUnified:
    """Test the unified crawl function for search results."""
    
    @pytest.fixture
    def mock_crawl_dependencies(self):
        """Mock dependencies for crawl_search_results_unified."""
        with patch('src.server.api_routes.knowledge_api.get_supabase_client') as mock_supabase, \
             patch('src.server.api_routes.knowledge_api.get_crawler') as mock_crawler, \
             patch('src.server.api_routes.knowledge_api.CrawlOrchestrationService') as mock_crawl_service, \
             patch('src.server.api_routes.knowledge_api.DocumentStorageOperations') as mock_doc_storage, \
             patch('src.server.api_routes.knowledge_api.start_crawl_progress') as mock_start, \
             patch('src.server.api_routes.knowledge_api.update_crawl_progress') as mock_update, \
             patch('src.server.api_routes.knowledge_api.complete_crawl_progress') as mock_complete, \
             patch('src.server.api_routes.knowledge_api.asyncio.sleep') as mock_sleep:
            
            mock_supabase.return_value = Mock()
            mock_crawler.return_value = AsyncMock()
            
            mock_crawl_instance = Mock()
            mock_crawl_instance.set_progress_id = Mock()
            mock_crawl_instance.crawl_batch_with_progress = AsyncMock(return_value=[
                {"url": "https://example.com/1", "content": "Content 1", "success": True},
                {"url": "https://example.com/2", "content": "Content 2", "success": True}
            ])
            mock_crawl_service.return_value = mock_crawl_instance
            
            mock_doc_instance = Mock()
            mock_doc_instance.process_and_store_documents = AsyncMock(return_value={"stored": 2})
            mock_doc_storage.return_value = mock_doc_instance
            
            mock_start.return_value = AsyncMock()
            mock_update.return_value = AsyncMock()
            mock_complete.return_value = AsyncMock()
            mock_sleep.return_value = AsyncMock()
            
            yield {
                'supabase': mock_supabase,
                'crawler': mock_crawler,
                'crawl_service': mock_crawl_service,
                'crawl_instance': mock_crawl_instance,
                'doc_storage': mock_doc_storage,
                'doc_instance': mock_doc_instance,
                'start_progress': mock_start,
                'update_progress': mock_update,
                'complete_progress': mock_complete,
                'sleep': mock_sleep
            }
    
    @pytest.mark.asyncio
    async def test_crawl_with_worker_updates(self, mock_crawl_dependencies):
        """Test that crawl properly updates worker statuses."""
        from src.server.api_routes.knowledge_api import crawl_search_results_unified
        
        await crawl_search_results_unified(
            search_term="test query",
            urls=["https://example.com/1", "https://example.com/2"],
            search_results=[
                {"url": "https://example.com/1", "title": "Page 1"},
                {"url": "https://example.com/2", "title": "Page 2"}
            ],
            progress_id="test_progress_123",
            knowledge_type="technical",
            tags=["test"],
            crawl_depth=1
        )
        
        # Verify initial progress includes workers
        initial_call = mock_crawl_dependencies['update_progress'].call_args_list[0]
        assert 'workers' in initial_call[0][1]
        workers = initial_call[0][1]['workers']
        assert len(workers) == 2
        assert workers[0]['worker_id'] == 'url_1'
        assert workers[0]['status'] == 'pending'
        assert workers[1]['worker_id'] == 'url_2'
        assert workers[1]['status'] == 'pending'
        
        # Verify crawler was called without arguments (important fix)
        mock_crawl_dependencies['crawler'].assert_called_with()
        
        # Verify service initialization with correct arguments
        mock_crawl_dependencies['crawl_service'].assert_called_with(
            mock_crawl_dependencies['crawler'].return_value,
            mock_crawl_dependencies['supabase'].return_value
        )
        
        # Verify delay was added for UI subscription
        mock_crawl_dependencies['sleep'].assert_called_with(2.0)
        
        # Verify completion includes workers
        complete_call = mock_crawl_dependencies['complete_progress'].call_args[0][1]
        assert 'workers' in complete_call
        assert complete_call['status'] == 'completed'
        assert complete_call['percentage'] == 100
    
    @pytest.mark.asyncio
    async def test_progress_callback_functionality(self, mock_crawl_dependencies):
        """Test that the progress callback updates workers correctly."""
        from src.server.api_routes.knowledge_api import crawl_search_results_unified
        
        # Track progress updates
        progress_updates = []
        mock_crawl_dependencies['update_progress'].side_effect = \
            lambda pid, data: progress_updates.append(data)
        
        await crawl_search_results_unified(
            search_term="test",
            urls=["https://example.com/1", "https://example.com/2", "https://example.com/3"],
            search_results=[
                {"url": "https://example.com/1", "title": "Page 1"},
                {"url": "https://example.com/2", "title": "Page 2"},
                {"url": "https://example.com/3", "title": "Page 3"}
            ],
            progress_id="test_123",
            knowledge_type="technical",
            tags=[],
            crawl_depth=1
        )
        
        # Get the progress callback that was passed
        crawl_call = mock_crawl_dependencies['crawl_instance'].crawl_batch_with_progress.call_args
        progress_callback = crawl_call[1]['progress_callback']
        
        # Test callback with different percentages
        await progress_callback("processing", 33, "Processing first URL")
        await progress_callback("processing", 66, "Processing second URL")
        await progress_callback("processing", 100, "All URLs processed")
        
        # Verify progress updates were made
        assert len(progress_updates) >= 4  # Initial + 3 callback updates
    
    @pytest.mark.asyncio
    async def test_crawl_error_handling(self, mock_crawl_dependencies):
        """Test that errors are properly handled during crawl."""
        from src.server.api_routes.knowledge_api import crawl_search_results_unified
        
        # Simulate crawler failure
        mock_crawl_dependencies['crawler'].side_effect = Exception("Crawler init failed")
        
        await crawl_search_results_unified(
            search_term="test",
            urls=["https://example.com"],
            search_results=[],
            progress_id="test_error",
            knowledge_type="technical",
            tags=[],
            crawl_depth=1
        )
        
        # Verify error was reported in progress
        error_call = mock_crawl_dependencies['update_progress'].call_args_list[-1]
        assert error_call[0][1]['status'] == 'error'
        assert 'error' in error_call[0][1]
        assert error_call[0][1]['completed'] == True


class TestProgressCallbackLogic:
    """Test the progress callback worker update logic."""
    
    def test_worker_status_calculation(self):
        """Test that worker statuses are calculated correctly based on percentage."""
        # Simulate the logic from the progress callback
        workers = [
            {"worker_id": "url_1", "status": "pending", "progress": 0},
            {"worker_id": "url_2", "status": "pending", "progress": 0},
            {"worker_id": "url_3", "status": "pending", "progress": 0},
            {"worker_id": "url_4", "status": "pending", "progress": 0}
        ]
        
        test_cases = [
            (0, [0, 0, 0, 0]),    # 0% - all pending
            (25, [100, 0, 0, 0]),  # 25% - first complete, second active
            (50, [100, 100, 0, 0]), # 50% - two complete
            (75, [100, 100, 100, 0]), # 75% - three complete
            (100, [100, 100, 100, 100]) # 100% - all complete
        ]
        
        for percentage, expected_progress in test_cases:
            # Calculate which workers should be active/completed
            if percentage > 0 and len(workers) > 0:
                progress_per_url = 100 / len(workers)
                completed_urls = int(percentage / progress_per_url)
                
                for idx in range(len(workers)):
                    if idx < completed_urls:
                        workers[idx]["status"] = "completed"
                        workers[idx]["progress"] = 100
                    elif idx == completed_urls and completed_urls < len(workers):
                        workers[idx]["status"] = "active"
                        workers[idx]["progress"] = int((percentage % progress_per_url) * (100 / progress_per_url))
                    else:
                        workers[idx]["status"] = "pending"
                        workers[idx]["progress"] = 0
            
            # Verify progress values
            actual_progress = [w["progress"] for w in workers]
            assert actual_progress == expected_progress, \
                f"At {percentage}%, expected {expected_progress}, got {actual_progress}"


class TestWebSocketIntegration:
    """Test WebSocket integration for progress updates."""
    
    @pytest.fixture
    def mock_sio(self):
        """Mock Socket.IO instance."""
        mock = Mock()
        mock.emit = AsyncMock()
        mock.enter_room = AsyncMock()
        mock.leave_room = AsyncMock()
        mock.rooms = Mock(return_value=['sid_123', 'search_progress_456'])
        return mock
    
    @pytest.mark.asyncio
    async def test_crawl_subscribe_event(self, mock_sio):
        """Test the crawl_subscribe Socket.IO event handler."""
        from src.server.api_routes.socketio_handlers import crawl_subscribe
        
        with patch('src.server.api_routes.socketio_handlers.sio', mock_sio), \
             patch('src.server.api_routes.socketio_handlers.logger') as mock_logger:
            
            await crawl_subscribe('sid_123', {'progress_id': 'search_abc123'})
            
            # Verify room was joined
            mock_sio.enter_room.assert_called_with('sid_123', 'search_abc123')
            
            # Verify acknowledgment was sent
            ack_calls = [c for c in mock_sio.emit.call_args_list 
                        if c[0][0] == 'crawl_subscribe_ack']
            assert len(ack_calls) > 0
            ack_data = ack_calls[0][0][1]
            assert ack_data['progress_id'] == 'search_abc123'
            assert ack_data['status'] == 'subscribed'
    
    @pytest.mark.asyncio
    async def test_crawl_unsubscribe_event(self, mock_sio):
        """Test the crawl_unsubscribe Socket.IO event handler."""
        from src.server.api_routes.socketio_handlers import crawl_unsubscribe
        
        with patch('src.server.api_routes.socketio_handlers.sio', mock_sio):
            await crawl_unsubscribe('sid_123', {'progress_id': 'search_abc123'})
            
            # Verify room was left
            mock_sio.leave_room.assert_called_with('sid_123', 'search_abc123')
    
    @pytest.mark.asyncio
    async def test_progress_broadcast(self, mock_sio):
        """Test that progress updates are broadcast correctly."""
        from src.server.api_routes.socketio_handlers import update_crawl_progress
        
        with patch('src.server.api_routes.socketio_handlers.sio', mock_sio):
            progress_data = {
                "progressId": "search_123",
                "status": "processing",
                "percentage": 50,
                "workers": [
                    {"worker_id": "url_1", "status": "completed", "progress": 100},
                    {"worker_id": "url_2", "status": "active", "progress": 50}
                ],
                "currentStep": "Crawling 1 of 2 URLs",
                "searchTerm": "test query"
            }
            
            await update_crawl_progress('search_123', progress_data)
            
            # Verify broadcast was made
            mock_sio.emit.assert_called()
            emit_calls = [c for c in mock_sio.emit.call_args_list 
                         if c[0][0] == 'crawl_progress']
            assert len(emit_calls) > 0
            
            # Verify data includes workers
            broadcast_data = emit_calls[0][0][1]
            assert 'workers' in broadcast_data
            assert broadcast_data['progressId'] == 'search_123'


@pytest.mark.integration
class TestEndToEndFlow:
    """Integration tests for the complete search and crawl flow."""
    
    @pytest.mark.asyncio
    async def test_complete_search_crawl_flow(self):
        """Test the complete flow from search to crawl completion."""
        # This test would run against actual services in a test environment
        # For unit testing, we mock everything
        
        from src.server.api_routes.knowledge_api import search_and_crawl
        
        with patch('src.server.api_routes.knowledge_api.brave_search_service') as mock_brave, \
             patch('src.server.api_routes.knowledge_api.crawl_search_results_unified') as mock_crawl:
            
            mock_brave.is_configured.return_value = True
            mock_brave.search_for_crawling = AsyncMock(return_value={
                "search_term": "integration test",
                "urls_to_crawl": ["https://test.com"],
                "search_results": [{"url": "https://test.com", "title": "Test"}],
                "result_count": 1
            })
            
            mock_crawl.return_value = AsyncMock()
            
            mock_request = Mock()
            background_tasks = AsyncMock()
            
            result = await search_and_crawl(
                request=mock_request,
                background_tasks=background_tasks,
                search_term="integration test",
                max_results=1
            )
            
            assert result['success'] == True
            assert 'crawl_progress_id' in result
            
            # Verify crawl was initiated
            mock_crawl.assert_called_once()
            call_args = mock_crawl.call_args[1]
            assert call_args['search_term'] == "integration test"
            assert len(call_args['urls']) == 1


if __name__ == "__main__":
    # Run tests with coverage
    pytest.main([__file__, "-v", "--cov=src.server", "--cov-report=term-missing"])