import React, { useState, useRef, useEffect } from 'react';
import { Send, Loader2, Search, X, Sparkles, Book, FileText, ChevronDown, Brain, Database, Eye } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '../ui/Button';
import { chatService } from '../../services/chatService';
import { useToast } from '../../contexts/ToastContext';

interface Message {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
  sources?: Array<{
    url: string;
    title?: string;
    similarity?: number;
    content?: string;
  }>;
  searchResults?: Array<{
    content: string;
    url?: string;
    source?: string;
    similarity?: number;
    metadata?: any;
  }>;
  reasoningSteps?: Array<{
    step: number;
    action?: string;
    action_input?: any;
    has_results?: boolean;
    result_count?: number;
    results_preview?: Array<{
      content: string;
      similarity: number;
      url?: string;
    }>;
    error?: string;
  }>;
  observations?: Array<{
    action: string;
    query?: string;
    has_results: boolean;
    results?: any[];
  }>;
  isStreaming?: boolean;
  error?: boolean;
}

interface KnowledgeChatProps {
  className?: string;
}

export const KnowledgeChat: React.FC<KnowledgeChatProps> = ({ className = '' }) => {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [showSources, setShowSources] = useState<{ [key: string]: boolean }>({});
  const [showSearchResults, setShowSearchResults] = useState<{ [key: string]: boolean }>({});
  const [showReasoning, setShowReasoning] = useState<{ [key: string]: boolean }>({});
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const { showToast } = useToast();

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    const userMessage: Message = {
      id: `user-${Date.now()}`,
      role: 'user',
      content: input.trim(),
      timestamp: new Date(),
    };

    setMessages(prev => [...prev, userMessage]);
    setInput('');
    setIsLoading(true);

    // Create assistant message that will be updated as streaming happens
    const assistantMessageId = `assistant-${Date.now()}`;
    const assistantMessage: Message = {
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      timestamp: new Date(),
      isStreaming: true,
    };
    setMessages(prev => [...prev, assistantMessage]);

    try {
      // Stream the response from the RAG agent
      await chatService.queryKnowledgeStream(
        userMessage.content,
        (chunk: string) => {
          // Update message content as chunks arrive
          setMessages(prev => prev.map(msg => 
            msg.id === assistantMessageId 
              ? { ...msg, content: msg.content + chunk }
              : msg
          ));
        },
        (completeData: any) => {
          // Update with all the search results, sources, and reasoning steps
          setMessages(prev => prev.map(msg => 
            msg.id === assistantMessageId 
              ? { 
                  ...msg, 
                  sources: completeData.sources || [],
                  searchResults: completeData.searchResults || [],
                  reasoningSteps: completeData.reasoningSteps || [],
                  observations: completeData.observations || [],
                  isStreaming: false 
                }
              : msg
          ));
        }
      );
    } catch (err) {
      console.error('Chat error:', err);
      
      // Determine the error message based on the error type
      let errorMessage = 'An unexpected error occurred. Please try again.';
      let toastMessage = 'Error';
      
      if (err instanceof Error) {
        errorMessage = err.message;
        
        // Determine toast message based on error content
        if (err.message.includes('timeout') || err.message.includes('timed out')) {
          toastMessage = 'Request timed out';
        } else if (err.message.includes('connect') || err.message.includes('network')) {
          toastMessage = 'Connection error';
        } else if (err.message.includes('model') || err.message.includes('AI')) {
          toastMessage = 'AI service error';
        } else if (err.message.includes('knowledge base') || err.message.includes('No relevant')) {
          toastMessage = 'No results found';
        } else {
          toastMessage = 'Service error';
        }
      }
      
      setMessages(prev => prev.map(msg => 
        msg.id === assistantMessageId 
          ? { 
              ...msg, 
              content: errorMessage,
              error: true,
              isStreaming: false
            }
          : msg
      ));
      showToast(toastMessage, 'error');
    } finally {
      setIsLoading(false);
      inputRef.current?.focus();
    }
  };

  const clearChat = () => {
    setMessages([]);
    setShowSources({});
    setShowSearchResults({});
    setShowReasoning({});
  };

  const toggleSources = (messageId: string) => {
    setShowSources(prev => ({ ...prev, [messageId]: !prev[messageId] }));
  };

  const exampleQuestions = [
    "What does this codebase do?",
    "Show me the main API endpoints",
    "How does authentication work?",
    "What are the key components?"
  ];

  return (
    <div className={`flex flex-col h-full bg-gray-50 dark:bg-gray-900 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b dark:border-gray-700 bg-white dark:bg-gray-800">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-green-100 dark:bg-green-900 rounded-lg">
            <Book className="h-5 w-5 text-green-600 dark:text-green-400" />
          </div>
          <div>
            <h2 className="text-lg font-semibold">Knowledge Chat</h2>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              Ask questions about your indexed content
            </p>
          </div>
        </div>
        {messages.length > 0 && (
          <Button
            variant="ghost"
            size="sm"
            onClick={clearChat}
            className="text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
          >
            <X className="h-4 w-4 mr-1" />
            Clear
          </Button>
        )}
      </div>

      {/* Messages Area */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-gray-500 dark:text-gray-400 py-8">
            <div className="p-4 bg-green-50 dark:bg-green-900/20 rounded-full mb-6">
              <Sparkles className="h-12 w-12 text-green-500 dark:text-green-400" />
            </div>
            <h3 className="text-xl font-semibold mb-2 text-gray-900 dark:text-gray-100">
              Start a conversation
            </h3>
            <p className="text-sm text-center max-w-md mb-8">
              Ask questions about your knowledge base. I'll search through your indexed documents 
              and provide relevant answers with sources.
            </p>
            
            <div className="w-full max-w-lg space-y-3">
              <p className="text-xs font-medium uppercase tracking-wide text-center mb-3">
                Try asking:
              </p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                {exampleQuestions.map((question, idx) => (
                  <button
                    key={idx}
                    onClick={() => setInput(question)}
                    className="text-left p-3 rounded-lg border border-gray-200 dark:border-gray-700 
                             bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-750 
                             transition-colors group"
                  >
                    <span className="text-sm text-gray-700 dark:text-gray-300 group-hover:text-green-600 dark:group-hover:text-green-400">
                      {question}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        ) : (
          <>
            <AnimatePresence initial={false}>
              {messages.map((message) => (
                <motion.div
                  key={message.id}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -20 }}
                  className={`flex ${message.role === 'user' ? 'justify-end' : 'justify-start'}`}
                >
                  <div
                    className={`max-w-[70%] rounded-lg ${
                      message.role === 'user'
                        ? 'bg-green-600 text-white p-4'
                        : message.error
                        ? 'bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-4'
                        : 'bg-white dark:bg-gray-800 shadow-md p-4'
                    }`}
                  >
                    {/* Message content */}
                    <div className={`text-sm whitespace-pre-wrap ${
                      message.error ? 'text-red-700 dark:text-red-400' : ''
                    }`}>
                      {message.content}
                    </div>
                    
                    {/* Action Buttons */}
                    <div className="mt-3 flex flex-wrap gap-2">
                      {/* Sources Button */}
                      {message.sources && message.sources.length > 0 && (
                        <button
                          onClick={() => toggleSources(message.id)}
                          className="flex items-center gap-1 text-xs font-medium text-gray-600 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 border border-gray-300 dark:border-gray-600 rounded px-2 py-1"
                        >
                          <FileText className="h-3 w-3" />
                          {message.sources.length} source{message.sources.length !== 1 ? 's' : ''}
                          <ChevronDown className={`h-3 w-3 transition-transform ${
                            showSources[message.id] ? 'rotate-180' : ''
                          }`} />
                        </button>
                      )}
                      
                      {/* Search Results Button */}
                      {message.searchResults && message.searchResults.length > 0 && (
                        <button
                          onClick={() => setShowSearchResults(prev => ({ ...prev, [message.id]: !prev[message.id] }))}
                          className="flex items-center gap-1 text-xs font-medium text-gray-600 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 border border-gray-300 dark:border-gray-600 rounded px-2 py-1"
                        >
                          <Database className="h-3 w-3" />
                          {message.searchResults.length} search result{message.searchResults.length !== 1 ? 's' : ''}
                          <ChevronDown className={`h-3 w-3 transition-transform ${
                            showSearchResults[message.id] ? 'rotate-180' : ''
                          }`} />
                        </button>
                      )}
                      
                      {/* Reasoning Steps Button */}
                      {message.reasoningSteps && message.reasoningSteps.length > 0 && (
                        <button
                          onClick={() => setShowReasoning(prev => ({ ...prev, [message.id]: !prev[message.id] }))}
                          className="flex items-center gap-1 text-xs font-medium text-gray-600 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 border border-gray-300 dark:border-gray-600 rounded px-2 py-1"
                        >
                          <Brain className="h-3 w-3" />
                          {message.reasoningSteps.length} reasoning step{message.reasoningSteps.length !== 1 ? 's' : ''}
                          <ChevronDown className={`h-3 w-3 transition-transform ${
                            showReasoning[message.id] ? 'rotate-180' : ''
                          }`} />
                        </button>
                      )}
                    </div>
                    
                    {/* Sources Section */}
                    <AnimatePresence>
                      {showSources[message.id] && message.sources && (
                        <motion.div
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: 'auto', opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          className="mt-2 pt-2 border-t border-gray-200 dark:border-gray-700 space-y-2 overflow-hidden"
                        >
                          <div className="text-xs font-semibold text-gray-700 dark:text-gray-300 mb-2">Referenced Sources:</div>
                          {message.sources.map((source, idx) => (
                            <div key={idx} className="flex items-start gap-2">
                              <Search className="h-3 w-3 text-gray-400 mt-0.5 flex-shrink-0" />
                              <div className="flex-1 min-w-0">
                                <a
                                  href={source.url}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="text-xs text-green-600 dark:text-green-400 hover:underline block truncate"
                                >
                                  {source.title || source.url}
                                </a>
                                {source.similarity !== undefined && (
                                  <span className="text-xs text-gray-500 dark:text-gray-400">
                                    {Math.round(source.similarity * 100)}% relevant
                                  </span>
                                )}
                              </div>
                            </div>
                          ))}
                        </motion.div>
                      )}
                    </AnimatePresence>
                    
                    {/* Search Results Section */}
                    <AnimatePresence>
                      {showSearchResults[message.id] && message.searchResults && (
                        <motion.div
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: 'auto', opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          className="mt-2 pt-2 border-t border-gray-200 dark:border-gray-700 space-y-3 overflow-hidden"
                        >
                          <div className="text-xs font-semibold text-gray-700 dark:text-gray-300 mb-2">All Search Results:</div>
                          {message.searchResults.map((result, idx) => (
                            <div key={idx} className="bg-gray-50 dark:bg-gray-750 rounded-lg p-3">
                              <div className="flex items-start justify-between mb-2">
                                <div className="flex items-center gap-2">
                                  <Eye className="h-3 w-3 text-gray-500" />
                                  <span className="text-xs font-medium text-gray-700 dark:text-gray-300">Result {idx + 1}</span>
                                </div>
                                {result.similarity !== undefined && (
                                  <span className="text-xs text-green-600 dark:text-green-400 font-medium">
                                    {Math.round(result.similarity * 100)}% match
                                  </span>
                                )}
                              </div>
                              <p className="text-xs text-gray-600 dark:text-gray-400 mb-2 line-clamp-3">
                                {result.content}
                              </p>
                              {result.url && (
                                <a
                                  href={result.url}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="text-xs text-green-600 dark:text-green-400 hover:underline"
                                >
                                  View source →
                                </a>
                              )}
                            </div>
                          ))}
                        </motion.div>
                      )}
                    </AnimatePresence>
                    
                    {/* Reasoning Steps Section */}
                    <AnimatePresence>
                      {showReasoning[message.id] && message.reasoningSteps && (
                        <motion.div
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: 'auto', opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          className="mt-2 pt-2 border-t border-gray-200 dark:border-gray-700 space-y-2 overflow-hidden"
                        >
                          <div className="text-xs font-semibold text-gray-700 dark:text-gray-300 mb-2">AI Reasoning Process:</div>
                          {message.reasoningSteps.map((step, idx) => (
                            <div key={idx} className="bg-gray-50 dark:bg-gray-750 rounded-lg p-3">
                              <div className="flex items-center gap-2 mb-1">
                                <span className="text-xs font-medium text-gray-700 dark:text-gray-300">
                                  Step {step.step}: {step.action}
                                </span>
                                {step.has_results && (
                                  <span className="text-xs text-green-600 dark:text-green-400">
                                    ✓ Found {step.result_count || 0} results
                                  </span>
                                )}
                                {step.error && (
                                  <span className="text-xs text-red-600 dark:text-red-400">
                                    ✗ Error
                                  </span>
                                )}
                              </div>
                              {step.action_input?.query && (
                                <p className="text-xs text-gray-600 dark:text-gray-400 italic">
                                  Query: "{step.action_input.query}"
                                </p>
                              )}
                              {step.results_preview && step.results_preview.length > 0 && (
                                <div className="mt-2 space-y-1">
                                  {step.results_preview.map((preview, pidx) => (
                                    <div key={pidx} className="text-xs text-gray-500 dark:text-gray-400">
                                      • {preview.content.substring(0, 100)}...
                                    </div>
                                  ))}
                                </div>
                              )}
                            </div>
                          ))}
                        </motion.div>
                      )}
                    </AnimatePresence>
                    
                    {/* Timestamp */}
                    <div className={`text-xs mt-2 ${
                      message.role === 'user' 
                        ? 'text-green-100' 
                        : 'text-gray-500 dark:text-gray-400'
                    }`}>
                      {new Date(message.timestamp).toLocaleTimeString()}
                    </div>
                  </div>
                </motion.div>
              ))}
            </AnimatePresence>

            {/* Loading indicator */}
            {isLoading && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                className="flex justify-start"
              >
                <div className="bg-white dark:bg-gray-800 rounded-lg p-4 shadow-md flex items-center gap-3">
                  <Loader2 className="h-5 w-5 animate-spin text-green-600" />
                  <span className="text-sm text-gray-600 dark:text-gray-400">
                    Searching knowledge base...
                  </span>
                </div>
              </motion.div>
            )}
          </>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Input Area */}
      <div className="border-t dark:border-gray-700 bg-white dark:bg-gray-800 p-4">
        <form onSubmit={handleSubmit} className="flex gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                handleSubmit(e);
              }
            }}
            placeholder="Ask a question about your knowledge base..."
            className="flex-1 resize-none rounded-lg border border-gray-300 dark:border-gray-600 
                     bg-gray-50 dark:bg-gray-900 px-4 py-3 text-sm 
                     focus:outline-none focus:ring-2 focus:ring-green-500 dark:focus:ring-green-400
                     placeholder-gray-500 dark:placeholder-gray-400"
            rows={2}
            disabled={isLoading}
          />
          <div className="flex flex-col justify-end">
            <Button
              type="submit"
              disabled={!input.trim() || isLoading}
              className="h-full"
              variant="primary"
            >
              {isLoading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Send className="h-4 w-4" />
              )}
            </Button>
          </div>
        </form>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-2">
          Press Enter to send, Shift+Enter for new line
        </p>
      </div>
    </div>
  );
};