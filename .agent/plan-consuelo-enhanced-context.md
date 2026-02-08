# Implementation Plan: Enhanced Context Gathering for @consuelo

## Overview

Enhance `.github/workflows/consuelo-tag-handler.yml` to read full file contents, calculate code metrics, and provide richer context to the AI assistant.

## Step-by-Step Implementation

### Step 1: Add Helper Functions (Top of Gather PR Context Step)

**Location:** `.github/workflows/consuelo-tag-handler.yml`, line 48 (inside script block)

**Add these utility functions:**

```javascript
// Utility: Determine if intent requires file contents
function needsFileContents(userPrompt, fileCount) {
  const keywords = ['test', 'review', 'code', 'function', 'class', 'implement', 'fix', 'bug', 'refactor', 'explain'];
  const hasKeyword = keywords.some(kw => userPrompt.toLowerCase().includes(kw));
  const smallPR = fileCount < 10;

  return hasKeyword || smallPR;
}

// Utility: Get file type from filename
function getFileType(filename) {
  const ext = filename.split('.').pop().toLowerCase();
  const typeMap = {
    'js': 'javascript', 'jsx': 'javascript',
    'ts': 'typescript', 'tsx': 'typescript',
    'py': 'python',
    'java': 'java',
    'go': 'go',
    'rs': 'rust',
    'cpp': 'cpp', 'cc': 'cpp', 'cxx': 'cpp',
    'c': 'c', 'h': 'c',
    'yml': 'yaml', 'yaml': 'yaml',
    'json': 'json',
    'md': 'markdown'
  };
  return typeMap[ext] || 'text';
}

// Utility: Estimate cyclomatic complexity
function estimateComplexity(content, filename) {
  const ext = filename.split('.').pop().toLowerCase();
  let score = 1;

  // Count control flow statements
  const controlFlow = ['if', 'else', 'for', 'while', 'switch', 'case', 'catch', 'try'];
  controlFlow.forEach(keyword => {
    const regex = new RegExp(`\\b${keyword}\\b`, 'g');
    const matches = content.match(regex);
    score += matches ? matches.length : 0;
  });

  // Count functions/methods
  if (['js', 'jsx', 'ts', 'tsx'].includes(ext)) {
    const funcMatches = content.match(/function\s+\w+|=>\s*{|^\s*\w+\s*\([^)]*\)\s*{/gm);
    score += funcMatches ? funcMatches.length * 0.5 : 0;
  } else if (ext === 'py') {
    const funcMatches = content.match(/^\s*def\s+\w+/gm);
    score += funcMatches ? funcMatches.length * 0.5 : 0;
  }

  return Math.min(100, Math.round(score));
}

// Utility: Extract imports from code
function extractImports(content, filename) {
  const ext = filename.split('.').pop().toLowerCase();
  const imports = [];

  if (['js', 'jsx', 'ts', 'tsx'].includes(ext)) {
    const importRegex = /import\s+(?:(?:\{[^}]+\}|\*\s+as\s+\w+|\w+)\s+from\s+)?['"]([^'"]+)['"]/g;
    const matches = content.matchAll(importRegex);
    for (const match of matches) {
      imports.push(match[1]);
    }
  } else if (ext === 'py') {
    const importRegex = /^(?:from\s+([\w.]+)\s+import|import\s+([\w.]+))/gm;
    const matches = content.matchAll(importRegex);
    for (const match of matches) {
      imports.push(match[1] || match[2]);
    }
  }

  return imports;
}

// Utility: Extract exports from code
function extractExports(content, filename) {
  const ext = filename.split('.').pop().toLowerCase();
  const exports = [];

  if (['js', 'jsx', 'ts', 'tsx'].includes(ext)) {
    const exportRegex = /export\s+(?:default\s+)?(?:class|function|const|let|var|interface|type|enum)\s+(\w+)/g;
    const matches = content.matchAll(exportRegex);
    for (const match of matches) {
      exports.push(match[1]);
    }
  } else if (ext === 'py') {
    // Python doesn't have explicit exports, but we can find top-level definitions
    const defRegex = /^(?:class|def)\s+(\w+)/gm;
    const matches = content.matchAll(defRegex);
    for (const match of matches) {
      if (!match[1].startsWith('_')) { // Public only
        exports.push(match[1]);
      }
    }
  }

  return exports;
}

// Utility: Extract code snippet around changed lines
function extractSnippets(content, patch) {
  if (!patch) return [];

  const lines = content.split('\n');
  const snippets = [];

  // Parse patch to find changed line numbers
  const patchLines = patch.split('\n');
  let currentLine = 0;

  for (const patchLine of patchLines) {
    // Look for hunk headers like @@ -1,5 +1,6 @@
    const hunkMatch = patchLine.match(/@@ -(\d+),?\d* \+(\d+),?\d* @@/);
    if (hunkMatch) {
      currentLine = parseInt(hunkMatch[2]);

      // Extract snippet: changed line +/- 10 lines
      const startLine = Math.max(0, currentLine - 10);
      const endLine = Math.min(lines.length, currentLine + 20); // 10 before, 20 after for context

      snippets.push({
        startLine: startLine + 1, // 1-indexed
        endLine: endLine,
        code: lines.slice(startLine, endLine).join('\n'),
        changedLine: currentLine
      });
    }
  }

  return snippets;
}

// Utility: Check if file is likely binary
function isBinaryFile(filename) {
  const binaryExts = ['.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.tar', '.gz', '.exe', '.dll', '.so', '.dylib', '.woff', '.woff2', '.ttf', '.eot'];
  return binaryExts.some(ext => filename.toLowerCase().endsWith(ext));
}
```

### Step 2: Modify File Changes Collection

**Location:** After line 80 (after fileChanges mapping)

**Replace the current approach with enhanced version:**

```javascript
// Determine if we should read file contents
const userPrompt = context.payload.comment.body.replace(/@consuelo\s*/i, '').trim();
const shouldReadFiles = needsFileContents(userPrompt, files.data.length);

console.log(`Should read file contents: ${shouldReadFiles} (files: ${files.data.length}, prompt: "${userPrompt}")`);

// Build comprehensive file changes with optional content reading
const fileContents = [];
const MAX_FILES = 20;
const MAX_FILE_SIZE = 100 * 1024; // 100KB
let totalSizeRead = 0;
const MAX_TOTAL_SIZE = 500 * 1024; // 500KB total

if (shouldReadFiles && files.data.length <= MAX_FILES) {
  console.log('Reading file contents...');

  for (const file of files.data) {
    // Skip binary files
    if (isBinaryFile(file.filename)) {
      fileContents.push({
        filename: file.filename,
        status: file.status,
        additions: file.additions,
        deletions: file.deletions,
        changes: file.changes,
        content: null,
        error: 'Binary file (skipped)',
        metrics: null,
        snippets: []
      });
      continue;
    }

    // Skip if deleted
    if (file.status === 'removed') {
      fileContents.push({
        filename: file.filename,
        status: file.status,
        additions: file.additions,
        deletions: file.deletions,
        changes: file.changes,
        content: null,
        error: 'File deleted',
        metrics: null,
        snippets: []
      });
      continue;
    }

    try {
      // Read file content from PR head
      const { data: fileContent } = await github.rest.repos.getContent({
        owner: context.repo.owner,
        repo: context.repo.repo,
        path: file.filename,
        ref: pr.data.head.ref
      });

      // Skip if too large
      if (fileContent.size > MAX_FILE_SIZE) {
        fileContents.push({
          filename: file.filename,
          status: file.status,
          additions: file.additions,
          deletions: file.deletions,
          changes: file.changes,
          content: null,
          error: `File too large (${Math.round(fileContent.size / 1024)}KB > 100KB)`,
          metrics: null,
          snippets: extractSnippets('', file.patch || '')
        });
        continue;
      }

      // Stop if we've read too much total
      if (totalSizeRead + fileContent.size > MAX_TOTAL_SIZE) {
        console.log('Reached total size limit, stopping file reads');
        break;
      }

      totalSizeRead += fileContent.size;

      // Decode content
      const content = Buffer.from(fileContent.content, 'base64').toString('utf8');
      const lines = content.split('\n');

      // Calculate metrics
      const metrics = {
        lines: lines.length,
        fileSize: fileContent.size,
        fileType: getFileType(file.filename),
        complexity: estimateComplexity(content, file.filename),
        imports: extractImports(content, file.filename),
        exports: extractExports(content, file.filename)
      };

      // Extract snippets around changed lines
      const snippets = extractSnippets(content, file.patch || '');

      // Decide whether to include full content or just snippets
      const includeFullContent = lines.length < 500 || file.status === 'added';

      fileContents.push({
        filename: file.filename,
        status: file.status,
        additions: file.additions,
        deletions: file.deletions,
        changes: file.changes,
        content: includeFullContent ? content : null,
        truncated: !includeFullContent,
        metrics,
        snippets: snippets.slice(0, 5) // Max 5 snippets per file
      });

      console.log(`Read ${file.filename}: ${lines.length} lines, complexity: ${metrics.complexity}`);

    } catch (error) {
      console.error(`Error reading ${file.filename}:`, error.message);
      fileContents.push({
        filename: file.filename,
        status: file.status,
        additions: file.additions,
        deletions: file.deletions,
        changes: file.changes,
        content: null,
        error: error.message,
        metrics: null,
        snippets: []
      });
    }
  }
} else {
  // Fallback to old behavior (just patches)
  console.log('Skipping file content reads (not needed or too many files)');
  files.data.forEach(f => {
    fileContents.push({
      filename: f.filename,
      status: f.status,
      additions: f.additions,
      deletions: f.deletions,
      changes: f.changes,
      patch: f.patch ? f.patch.substring(0, 5000) : null
    });
  });
}
```

### Step 3: Update Context Object

**Location:** Replace lines 90-101

```javascript
const context = {
  prNumber: context.issue.number,
  title: pr.data.title,
  body: pr.data.body || '',
  baseBranch: pr.data.base.ref,
  headBranch: pr.data.head.ref,
  additions: pr.data.additions,
  deletions: pr.data.deletions,
  changedFiles: pr.data.changed_files,
  fileChanges: fileContents, // Now includes content, metrics, and snippets
  commits: commitHistory,
  metadata: {
    filesRead: fileContents.filter(f => f.content !== null).length,
    totalSizeRead: totalSizeRead,
    enhancedContext: shouldReadFiles
  }
};

console.log(`Context built: ${fileContents.length} files, ${context.metadata.filesRead} read`);
```

### Step 4: Update AI Prompt

**Location:** `.github/workflows/consuelo-tag-handler.yml`, line 146

**Enhance the instructions:**

```yaml
          # Instructions
          - Provide a comprehensive, helpful response
          - For commit messages: analyze ALL commits and file changes, suggest a single conventional commit message that captures the entire PR
          - For code reviews: examine the actual code changes and provide specific feedback with line numbers
          - For test requests: use the provided file contents and code structure to suggest specific test cases
          - When file contents are available, reference specific functions, classes, and code patterns
          - Format your response in GitHub-flavored markdown
          - Be concise but thorough
          - Don't truncate lists - show everything relevant
```

## Testing Checklist

After implementation:

1. **Test Case 1: Small PR with code review request**
   - Create PR with 1-2 files
   - Comment: `@consuelo review this code`
   - Expected: Full file contents read, detailed review with line numbers

2. **Test Case 2: Large PR**
   - Create PR with 25+ files
   - Comment: `@consuelo summarize changes`
   - Expected: Only patches used, no full content reads

3. **Test Case 3: Test generation request**
   - Create PR with new function
   - Comment: `@consuelo write tests for this function`
   - Expected: File contents read, test suggestions based on actual code

4. **Test Case 4: Binary file handling**
   - Create PR with image file
   - Comment: `@consuelo describe changes`
   - Expected: Binary file skipped gracefully

5. **Test Case 5: Deleted file**
   - Create PR that deletes a file
   - Comment: `@consuelo explain why this was removed`
   - Expected: Deleted file handled, no read error

## Performance Expectations

- **Small PR (1-5 files):** +2-5 seconds for file reads
- **Medium PR (6-10 files):** +5-10 seconds for file reads
- **Large PR (>10 files):** Falls back to patch-only (no extra time)

## Error Handling Scenarios

1. **404 File Not Found:** File in PR but not in repo (rare) → Skip with error message
2. **403 Permission Denied:** Private submodule → Skip with error message
3. **Binary File Detection:** Skip with note "Binary file (skipped)"
4. **File Too Large:** Skip with note "File too large (XKB > 100KB)"
5. **Total Size Limit:** Stop reading after 500KB total → Log and use what was read

## Files Modified

- `.github/workflows/consuelo-tag-handler.yml` (lines 48-107)

## Rollback Plan

If issues occur:
1. Revert to commit before changes
2. Add `shouldReadFiles = false` override at top of script
3. Remove file content reading logic, keep only patch-based approach

## Next Steps

1. ✅ Plan completed
2. ⏭️ Implement changes to workflow file
3. ⏭️ Create test PR
4. ⏭️ Test with different scenarios
5. ⏭️ Commit and document
