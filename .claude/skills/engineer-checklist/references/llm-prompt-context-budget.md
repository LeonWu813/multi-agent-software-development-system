# LLM Prompt Context Window Budget

When building features that concatenate user-supplied text into LLM prompts, engineers must address context window limits before implementation begins — not after QA hits a 400/500 error from the LLM API.

## Required design decisions (resolve in spec before coding)

1. **Budget limit:** What is the maximum number of tokens to allocate to the dynamic/user-supplied portion of the prompt? This must account for the model's total context window minus the size of the fixed system prompt and expected response.

2. **Selection policy:** If user content exceeds the budget, which content is kept?
   - Recency-first (newest documents) — appropriate for "current knowledge base" use cases
   - Relevance-first (semantic similarity to query) — appropriate for RAG use cases
   - User-controlled — user explicitly selects which documents to include

3. **Truncation vs. rejection:** When content exceeds the budget, does the system silently truncate (keeping as much as fits), reject the request with a user-readable error, or warn the user and proceed with truncated content?

4. **Warning/logging policy:** The system should log a structured warning identifying what was excluded from the prompt whenever truncation occurs. Silent truncation produces output that is correct but incomplete, which is worse than a visible warning.

## Implementation pattern (recency-first truncation)

```typescript
const MAX_CONTEXT_CHARS = BUDGET_TOKENS * CHARS_PER_TOKEN; // e.g. 150_000 * 4 = 600_000
const sorted = docs.sort((a, b) => b.uploadedAt - a.uploadedAt); // newest first
let total = 0;
const included: Doc[] = [];
const excluded: Doc[] = [];
for (const doc of sorted) {
  if (total + doc.extractedText.length <= MAX_CONTEXT_CHARS) {
    included.push(doc);
    total += doc.extractedText.length;
  } else {
    excluded.push(doc);
  }
}
if (excluded.length > 0) {
  console.warn('Context window truncation', {
    excludedCount: excluded.length,
    excluded: excluded.map(d => ({ id: d.id, filename: d.filename })),
  });
}
```

## Token estimation

LLM APIs count tokens, not characters. A commonly used approximation is 4 characters per token for English prose. For safety, set the character budget to 80–90% of the token budget × 4 to leave headroom for tokenization variance and the fixed prompt portions.

## Self-check items

Before handing off any module that constructs LLM prompts:
- [ ] Context budget limit is defined as a named constant with a comment explaining the token math
- [ ] Selection policy is implemented and tested with inputs that exceed the budget
- [ ] Truncation warning log identifies excluded content by id and human-readable name
- [ ] Unit tests cover the at-budget boundary (total chars == budget) and the over-budget case (one doc excluded)
