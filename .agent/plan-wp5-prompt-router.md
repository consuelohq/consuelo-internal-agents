# Implementation Plan: AI Prompt Router

**Task:** consuelo_on_call_coaching-wp5
**Status:** READY FOR IMPLEMENTATION
**Estimated Time:** 12-18 hours total

---

## Overview

Build a centralized **Prompt Router** system to manage all AI requests across 4 different types:
1. Sales Coaching (real-time during calls)
2. Chat/Underwriting (with RAG)
3. Call Analytics (post-call review)
4. CSV Mapping (field intelligence)

**Goals:**
- Centralize prompt management
- Enable versioning and A/B testing
- Improve maintainability
- Add proper logging and error handling
- No breaking changes to existing endpoints

---

## Implementation Steps

### STEP 1: Create Directory Structure
**Time:** 5 minutes
**Priority:** HIGH

**Actions:**
```bash
mkdir -p app/prompts/templates
touch app/prompts/__init__.py
touch app/prompts/request_types.py
touch app/prompts/prompt_configs.py
touch app/prompts/prompt_router.py
touch app/prompts/groq_client.py
touch app/prompts/utils.py
touch app/prompts/templates/__init__.py
touch app/prompts/templates/coaching.py
touch app/prompts/templates/chat.py
touch app/prompts/templates/analytics.py
touch app/prompts/templates/csv_mapping.py
```

**Validation:**
- All files created
- Directory structure matches plan

---

### STEP 2: Implement Core Data Models
**Time:** 30 minutes
**Priority:** HIGH
**Files:** `app/prompts/request_types.py`, `app/prompts/prompt_configs.py`

**File 1: `request_types.py`**
```python
from enum import Enum
from dataclasses import dataclass
from typing import Dict, Any, Optional

class RequestType(Enum):
    """Types of AI requests supported by the router"""
    SALES_COACHING = "sales_coaching"
    CHAT_UNDERWRITING = "chat_underwriting"
    CALL_ANALYTICS = "call_analytics"
    CSV_MAPPING = "csv_mapping"

@dataclass
class RouterRequest:
    """Input to the prompt router"""
    request_type: RequestType
    context_data: Dict[str, Any]
    user_id: str
    endpoint: str
    metadata: Optional[Dict[str, Any]] = None
```

**File 2: `prompt_configs.py`**
```python
from dataclasses import dataclass
from typing import Optional, Dict, Any
from .request_types import RequestType

@dataclass
class PromptConfig:
    """Configuration for a prompt request"""
    request_type: RequestType
    system_message: str
    user_message_template: str
    template_vars: Dict[str, Any]

    # Groq API parameters
    model: str = "deepseek-r1-distill-llama-70b"
    temperature: float = 0.3
    max_tokens: int = 1500

    # Response handling
    streaming: bool = False
    response_format: str = "json"  # json, pydantic, text, stream
    pydantic_model: Optional[type] = None

    # Additional flags
    requires_rag: bool = False
    enable_thinking: bool = False

@dataclass
class RouterResponse:
    """Output from the prompt router"""
    success: bool
    response: Any  # Parsed response (Pydantic, dict, str, or SSE generator)
    error: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
```

**Validation:**
- Files parse without errors
- Import statements work
- Type hints are correct

---

### STEP 3: Extract Prompt Templates
**Time:** 2 hours
**Priority:** HIGH
**Files:** All `app/prompts/templates/*.py` files

**File 1: `templates/coaching.py`**
- Extract from: `app/script.py:3770-3785`
- Variables: `context`, `conversation`, `last_message`
- Model: `SalesCoaching` Pydantic
- Params: temp=0.4, max_tokens=1000

**File 2: `templates/chat.py`**
- Extract from: `app/langgraph_chat.py:299-350`
- Variables: `transcript`, `context_docs`, `query_type`
- Streaming: True
- Params: temp=0.3, max_tokens=2000

**File 3: `templates/analytics.py`**
- Extract from: `app/script.py:3877-3916`
- Variables: `full_transcript`
- Model: `CallAnalytics` Pydantic (parsed from JSON)
- Params: temp=0.3, max_tokens=1500

**File 4: `templates/csv_mapping.py`**
- Extract from: `app/script.py:14036-14068`
- Variables: `headers`, `sample_rows`, `target_fields`, `mode`
- Response: JSON dict
- Params: temp=0.1, max_tokens=1000

**Template Format Example:**
```python
from ..prompt_configs import PromptConfig
from ..request_types import RequestType

def get_coaching_prompt_config(**kwargs) -> PromptConfig:
    """Get prompt config for sales coaching"""
    context = kwargs.get('context', '')
    conversation = kwargs.get('conversation', '')
    last_message = kwargs.get('last_message', '')

    system_message = "You are providing real-time sales coaching. Be direct and actionable."

    user_message_template = f"""
Product Context:
{context}

Recent Conversation:
{conversation}

Customer's Last Statement: {last_message}

Provide:
1. EMOTIONAL TRIGGER (for 'product_or_option_name'): What fear/pain to leverage
2. ACTIONABLE PHRASES: 1-3 **bold** exact phrases the agent can say RIGHT NOW
3. PAIN FUNNEL QUESTIONS: 2-3 questions to dig deeper

NO summaries. NO explanations. ONLY actionable content.
"""

    return PromptConfig(
        request_type=RequestType.SALES_COACHING,
        system_message=system_message,
        user_message_template=user_message_template,
        template_vars=kwargs,
        model="deepseek-r1-distill-llama-70b",
        temperature=0.4,
        max_tokens=1000,
        streaming=False,
        response_format="pydantic",
        pydantic_model=None,  # Will import SalesCoaching from script.py
    )
```

**Validation:**
- All 4 templates created
- Variables match original prompts
- Parameters match original API calls
- No syntax errors

---

### STEP 4: Implement Groq Client Wrapper
**Time:** 1.5 hours
**Priority:** HIGH
**File:** `app/prompts/groq_client.py`

**Key Functions:**
1. `call_groq_api(messages, config)` - Main entry point
2. `parse_response(response, format, model)` - Parse based on format
3. `handle_streaming_response(response)` - Streaming generator
4. `handle_pydantic_response(response, model)` - Pydantic parsing

**Error Handling:**
- Import logger + Sentry
- Try/catch on API calls
- Fallback for network errors
- Log all errors with context

**Example Structure:**
```python
from groq import Groq
import os
import json
from typing import Any, Generator, Optional
from .prompt_configs import PromptConfig, RouterResponse
import logger  # Use existing logger
import Sentry  # Use existing Sentry

groq_client = Groq(api_key=os.getenv("GROQ_API_KEY"))

def call_groq_api(
    messages: list,
    config: PromptConfig
) -> RouterResponse:
    """Call Groq API with configuration"""
    try:
        response = groq_client.chat.completions.create(
            model=config.model,
            messages=messages,
            temperature=config.temperature,
            max_tokens=config.max_tokens,
            stream=config.streaming
        )

        if config.streaming:
            # Return generator
            return RouterResponse(
                success=True,
                response=_handle_streaming(response)
            )
        else:
            # Parse response
            parsed = _parse_response(
                response,
                config.response_format,
                config.pydantic_model
            )
            return RouterResponse(success=True, response=parsed)

    except Exception as e:
        logger.error(f"[PromptRouter] Groq API call failed", {
            'request_type': config.request_type.value,
            'error': str(e)
        })
        Sentry.captureException(e)
        return RouterResponse(
            success=False,
            response=None,
            error=str(e)
        )

def _parse_response(response, format_type, pydantic_model):
    """Parse response based on format"""
    content = response.choices[0].message.content

    if format_type == "json":
        return json.loads(content)
    elif format_type == "pydantic":
        # Parse JSON then convert to Pydantic
        data = json.loads(content)
        return pydantic_model(**data)
    elif format_type == "text":
        return content
    else:
        return content

def _handle_streaming(response) -> Generator:
    """Handle streaming responses"""
    for chunk in response:
        if chunk.choices[0].delta.content:
            yield chunk.choices[0].delta.content
```

**Validation:**
- Import Groq successfully
- Error handling works
- Logger + Sentry integration
- No breaking changes to response types

---

### STEP 5: Implement Router Logic
**Time:** 2 hours
**Priority:** HIGH
**File:** `app/prompts/prompt_router.py`

**Key Functions:**
1. `route_prompt_request(request: RouterRequest) -> RouterResponse`
   - Main entry point
   - Classifies request type
   - Gets prompt config
   - Builds messages
   - Calls Groq API

2. `classify_request(endpoint: str, context: dict) -> RequestType`
   - Map endpoint to request type
   - Handle edge cases

3. `get_prompt_config(request_type: RequestType, **kwargs) -> PromptConfig`
   - Load appropriate template
   - Inject context variables

4. `build_groq_messages(config: PromptConfig) -> list`
   - Assemble message payload
   - System + user message

**Example Structure:**
```python
from typing import Dict, Any
from .request_types import RequestType, RouterRequest
from .prompt_configs import PromptConfig, RouterResponse
from .templates import coaching, chat, analytics, csv_mapping
from .groq_client import call_groq_api
import logger

def route_prompt_request(request: RouterRequest) -> RouterResponse:
    """Main entry point for prompt routing"""
    try:
        # Get prompt configuration
        config = get_prompt_config(
            request.request_type,
            **request.context_data
        )

        # Build messages
        messages = build_groq_messages(config)

        # Log request
        logger.info(f"[PromptRouter] Routing request", {
            'user_id': request.user_id,
            'request_type': request.request_type.value,
            'endpoint': request.endpoint
        })

        # Call Groq API
        response = call_groq_api(messages, config)

        return response

    except Exception as e:
        logger.error(f"[PromptRouter] Routing failed", {
            'user_id': request.user_id,
            'request_type': request.request_type.value,
            'error': str(e)
        })
        return RouterResponse(
            success=False,
            response=None,
            error=str(e)
        )

def classify_request(endpoint: str, context: dict) -> RequestType:
    """Classify request type from endpoint"""
    if '/sales_tips' in endpoint or '/talking_points' in endpoint:
        return RequestType.SALES_COACHING
    elif '/api/chat/' in endpoint:
        return RequestType.CHAT_UNDERWRITING
    elif '/api/analytics/' in endpoint:
        return RequestType.CALL_ANALYTICS
    elif '/analyze-csv' in endpoint:
        return RequestType.CSV_MAPPING
    else:
        raise ValueError(f"Unknown endpoint: {endpoint}")

def get_prompt_config(request_type: RequestType, **kwargs) -> PromptConfig:
    """Get prompt configuration for request type"""
    if request_type == RequestType.SALES_COACHING:
        return coaching.get_coaching_prompt_config(**kwargs)
    elif request_type == RequestType.CHAT_UNDERWRITING:
        return chat.get_chat_prompt_config(**kwargs)
    elif request_type == RequestType.CALL_ANALYTICS:
        return analytics.get_analytics_prompt_config(**kwargs)
    elif request_type == RequestType.CSV_MAPPING:
        return csv_mapping.get_csv_mapping_prompt_config(**kwargs)
    else:
        raise ValueError(f"Unknown request type: {request_type}")

def build_groq_messages(config: PromptConfig) -> list:
    """Build message payload for Groq API"""
    messages = []

    if config.system_message:
        messages.append({
            "role": "system",
            "content": config.system_message
        })

    messages.append({
        "role": "user",
        "content": config.user_message_template
    })

    return messages
```

**Validation:**
- All request types classified correctly
- Prompt configs loaded
- Messages built correctly
- Error handling works

---

### STEP 6: Integrate with Sales Coaching
**Time:** 1.5 hours
**Priority:** HIGH
**File:** `app/script.py` (around line 3760-3852)

**Current Code (script.py:3760-3852):**
```python
def generate_contextual_coaching(context_chunks, current_conv, call_sid):
    # Build prompt inline
    prompt = "You are providing real-time sales coaching..."

    response = chat_client.chat.completions.create(
        model=CHAT_MODEL,
        messages=[...],
        temperature=0.4,
        max_tokens=1000
    )

    # Parse into SalesCoaching Pydantic
    ...
```

**New Code:**
```python
from prompts.prompt_router import route_prompt_request
from prompts.request_types import RequestType, RouterRequest

def generate_contextual_coaching(context_chunks, current_conv, call_sid):
    """Generate coaching tips using prompt router"""

    # Get last message
    last_message = ""
    if current_conv and len(current_conv) > 0:
        last_message = current_conv[-1].get('content', '')

    # Build router request
    router_request = RouterRequest(
        request_type=RequestType.SALES_COACHING,
        context_data={
            'context': context_chunks,
            'conversation': current_conv,
            'last_message': last_message
        },
        user_id=current_conv[0].get('user_id', 'unknown'),
        endpoint='/sales_tips'
    )

    # Route through prompt router
    result = route_prompt_request(router_request)

    if not result.success:
        logger.error(f"[Coaching] Failed to generate tips", {
            'call_sid': call_sid,
            'error': result.error
        })
        return None

    # Result.response is already parsed SalesCoaching Pydantic
    return result.response
```

**Changes:**
1. Remove hardcoded prompt (lines ~3770-3785)
2. Add router import
3. Build RouterRequest
4. Call route_prompt_request()
5. Handle response

**Validation:**
- Function signature unchanged
- Return type unchanged (SalesCoaching Pydantic)
- Redis/MongoDB storage still works
- Endpoints still return correct data

---

### STEP 7: Integrate with Chat/Underwriting
**Time:** 2 hours
**Priority:** HIGH
**Files:** `app/langgraph_chat.py`, `app/chat_routes_v2.py`

**Current Code (langgraph_chat.py:299-350):**
```python
def _build_system_prompt(self, state: ChatState) -> str:
    base_prompt = "You are an AI assistant..."
    # Add transcript if available
    # Add context docs if available
    return base_prompt
```

**New Code:**
```python
from prompts.templates.chat import get_chat_prompt_config

def _build_system_prompt(self, state: ChatState) -> str:
    """Build system prompt using router templates"""

    config = get_chat_prompt_config(
        transcript=state.get('transcript', ''),
        context_docs=state.get('context_docs', []),
        query_type=state.get('query_type', 'general')
    )

    return config.system_message
```

**Note:** Chat uses streaming, so we need to preserve that. The router should return a generator for streaming responses.

**Validation:**
- Streaming still works
- RAG integration preserved
- SSE responses unchanged
- Frontend receives expected format

---

### STEP 8: Integrate with Call Analytics
**Time:** 1 hour
**Priority:** MEDIUM
**File:** `app/script.py` (around line 3854-4000)

**Current Code:**
```python
def generate_call_analytics(call_sid, user_id, phone_number, transcript_data):
    analytics_prompt = f"""Analyze this sales call..."""

    response = chat_client.chat.completions.create(...)

    # Parse JSON into CallAnalytics
    ...
```

**New Code:**
```python
from prompts.prompt_router import route_prompt_request
from prompts.request_types import RequestType, RouterRequest

def generate_call_analytics(call_sid, user_id, phone_number, transcript_data):
    """Generate call analytics using prompt router"""

    router_request = RouterRequest(
        request_type=RequestType.CALL_ANALYTICS,
        context_data={
            'full_transcript': transcript_data
        },
        user_id=user_id,
        endpoint=f'/api/analytics/{call_sid}'
    )

    result = route_prompt_request(router_request)

    if not result.success:
        logger.error(f"[Analytics] Failed to generate analytics", {
            'call_sid': call_sid,
            'error': result.error
        })
        return None

    return result.response  # Already parsed CallAnalytics
```

**Validation:**
- Response is CallAnalytics Pydantic
- MongoDB storage works
- Endpoint returns correct data

---

### STEP 9: Integrate with CSV Mapping
**Time:** 1 hour
**Priority:** MEDIUM
**File:** `app/script.py` (around line 13992-14130)

**Current Code:**
```python
def analyze_csv_mapping():
    prompt = f"""You are a CSV field mapping expert..."""

    response = chat_client.chat.completions.create(
        model=CHAT_MODEL,
        messages=[
            {"role": "system", "content": "You are a data mapping expert..."},
            {"role": "user", "content": prompt}
        ],
        temperature=0.1,
        max_tokens=1000
    )

    result = json.loads(response.choices[0].message.content)
    return result
```

**New Code:**
```python
from prompts.prompt_router import route_prompt_request
from prompts.request_types import RequestType, RouterRequest

def analyze_csv_mapping(headers, sample_rows, target_fields, mode):
    """Analyze CSV mapping using prompt router"""

    router_request = RouterRequest(
        request_type=RequestType.CSV_MAPPING,
        context_data={
            'headers': headers,
            'sample_rows': sample_rows,
            'target_fields': target_fields,
            'mode': mode
        },
        user_id=get_request_user_id(),  # From existing auth
        endpoint='/api/contacts/analyze-csv'
    )

    result = route_prompt_request(router_request)

    if not result.success:
        logger.error(f"[CSV] Failed to analyze mapping", {
            'error': result.error
        })
        return {'error': result.error}

    return result.response  # Already parsed JSON dict
```

**Validation:**
- Response is JSON dict
- Frontend receives expected format
- CSV upload workflow unchanged

---

### STEP 10: Add Comprehensive Logging
**Time:** 30 minutes
**Priority:** HIGH
**Files:** All router files

**Add to every function:**
```python
import logger
import Sentry

# At entry points
logger.info(f"[PromptRouter] Processing request", {
    'user_id': user_id,
    'request_type': request_type.value,
    'endpoint': endpoint
})

# On errors
logger.error(f"[PromptRouter] Request failed", {
    'user_id': user_id,
    'request_type': request_type.value,
    'error': str(e)
})
Sentry.captureException(e)
```

**Validation:**
- Logs appear in PostHog
- Sentry captures errors
- No console.log/error usage

---

### STEP 11: Update Exports & Imports
**Time:** 30 minutes
**Priority:** HIGH
**File:** `app/prompts/__init__.py`

**Content:**
```python
from .prompt_router import route_prompt_request, classify_request
from .request_types import RequestType, RouterRequest
from .prompt_configs import PromptConfig, RouterResponse

__all__ = [
    'route_prompt_request',
    'classify_request',
    'RequestType',
    'RouterRequest',
    'PromptConfig',
    'RouterResponse',
]
```

**Validation:**
- All imports work
- No circular dependencies

---

### STEP 12: Write Unit Tests
**Time:** 2 hours
**Priority:** MEDIUM
**File:** `app/test_prompt_router.py`

**Test Cases:**
1. Request classification (endpoint → RequestType)
2. Prompt config loading (all 4 types)
3. Message building
4. Response parsing (JSON, Pydantic, text)
5. Error handling
6. Logging

**Example:**
```python
import pytest
from prompts.prompt_router import classify_request, get_prompt_config
from prompts.request_types import RequestType

def test_classify_sales_coaching():
    request_type = classify_request('/sales_tips', {})
    assert request_type == RequestType.SALES_COACHING

def test_classify_chat():
    request_type = classify_request('/api/chat/v2/send_message', {})
    assert request_type == RequestType.CHAT_UNDERWRITING

def test_coaching_prompt_config():
    config = get_prompt_config(
        RequestType.SALES_COACHING,
        context='Product info',
        conversation='Hi there',
        last_message='Tell me more'
    )
    assert config.temperature == 0.4
    assert config.max_tokens == 1000
    assert 'Product info' in config.user_message_template
```

**Validation:**
- All tests pass
- Mock Groq API for tests
- No actual API calls in tests

---

### STEP 13: End-to-End Testing
**Time:** 2 hours
**Priority:** HIGH

**Test Scenarios:**
1. Start active call → Verify sales coaching tips generated
2. Send chat message → Verify streaming response
3. Generate call analytics → Verify analytics JSON
4. Upload CSV → Verify field mappings

**Commands:**
```bash
# Start all services
npm start

# Test coaching (requires active call)
curl "http://localhost:5000/sales_tips?call_sid=test123"

# Test chat
curl -X POST "http://localhost:5000/api/chat/v2/send_message" \
  -H "Content-Type: application/json" \
  -d '{"message": "Is this the right policy?", "session_id": "test"}'

# Test analytics
curl -X POST "http://localhost:5000/api/analytics/test123/generate"

# Test CSV mapping (via frontend)
# Upload CSV in FileManager
```

**Validation:**
- All 4 request types work
- No breaking changes
- Performance within 10% of baseline
- No errors in logs

---

### STEP 14: Update Documentation
**Time:** 30 minutes
**Priority:** HIGH
**File:** `/Users/kokayi/Dev/consuelo_on_call_coaching/CLAUDE.md`

**Add Section:**
```markdown
## Prompt Router Architecture

The application uses a centralized **Prompt Router** to manage all AI requests:

**Location:** `app/prompts/`

**Request Types:**
1. Sales Coaching - Real-time tips during calls
2. Chat/Underwriting - Q&A with RAG
3. Call Analytics - Post-call performance review
4. CSV Mapping - Intelligent field mapping

**Usage:**
```python
from prompts.prompt_router import route_prompt_request
from prompts.request_types import RequestType, RouterRequest

request = RouterRequest(
    request_type=RequestType.SALES_COACHING,
    context_data={'context': '...', 'conversation': '...'},
    user_id=user_id,
    endpoint='/sales_tips'
)
result = route_prompt_request(request)
```

**Files:**
- `prompt_router.py` - Main routing logic
- `request_types.py` - Enums and data models
- `prompt_configs.py` - Configuration models
- `groq_client.py` - Groq API wrapper
- `templates/*.py` - Prompt templates

**Adding New Request Types:**
1. Add enum to `RequestType`
2. Create template in `templates/`
3. Add case in `get_prompt_config()`
4. Update classification logic
```

**Validation:**
- Documentation clear
- Examples work
- Architecture diagram updated

---

### STEP 15: Commit Changes
**Time:** 15 minutes
**Priority:** HIGH

**Commit Message:**
```
feat: Add centralized AI prompt router for request type handling

- Create app/prompts/ module with router architecture
- Extract 4 prompt types: coaching, chat, analytics, CSV
- Implement request classification and routing logic
- Add Groq API wrapper with error handling
- Integrate router with all existing endpoints
- Add comprehensive logging (logger + Sentry)
- Add unit tests for router functionality
- Update CLAUDE.md with router documentation

All existing endpoints remain backward compatible.
No breaking changes to API responses.

Request types supported:
- Sales Coaching (real-time during calls)
- Chat/Underwriting (with RAG)
- Call Analytics (post-call review)
- CSV Mapping (field intelligence)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## Testing Checklist

- [ ] All 4 request types classified correctly
- [ ] Prompt templates render without errors
- [ ] Groq API calls succeed for all types
- [ ] Response parsing works (JSON, Pydantic, streaming)
- [ ] Error handling catches and logs failures
- [ ] Logger + Sentry integration works
- [ ] Unit tests pass (pytest)
- [ ] E2E tests pass (manual or Playwright)
- [ ] No breaking changes to existing endpoints
- [ ] Performance within 10% of baseline
- [ ] Documentation updated

---

## Rollback Plan

If issues occur:
1. Revert commit
2. Remove `app/prompts/` directory
3. Restore original imports in `script.py`, `langgraph_chat.py`
4. Restart Flask apps

---

## Future Enhancements (Out of Scope)

- Prompt versioning (A/B testing)
- Prompt caching (Redis)
- Multi-model support (OpenAI, Anthropic, etc.)
- Prompt analytics dashboard
- Dynamic prompt optimization based on response quality
- Rate limiting per request type
- Cost tracking per request type

---

## Success Metrics

- ✅ All 4 request types use router
- ✅ Zero breaking changes
- ✅ Prompts in config files, not inline
- ✅ Tests cover all request types
- ✅ Proper error tracking
- ✅ Performance regression < 10%
- ✅ Documentation complete

---

## Ready to Implement

All prerequisites met:
- Research complete
- Architecture designed
- Plan documented
- Risk assessment done

**Next:** Execute implementation steps 1-15 in order.
