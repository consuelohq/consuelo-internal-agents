"""Diff analysis and pattern detection."""

import re
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass

from conventional import ConventionalComment, Label, Decoration


@dataclass
class DiffHunk:
    """A section of diff."""
    file_path: str
    start_line: int
    lines: List[str]
    added_lines: List[Tuple[int, str]]  # (line_number, content)
    removed_lines: List[Tuple[int, str]]


class DiffAnalyzer:
    """Analyzes code diffs for issues and patterns."""
    
    def __init__(self):
        self.patterns = self._init_patterns()
    
    def _init_patterns(self) -> Dict[str, List[re.Pattern]]:
        """Initialize regex patterns for detecting issues."""
        return {
            "sql_injection": [
                re.compile(r'["\']SELECT.*WHERE.*\{["\']'),
                re.compile(r'["\']SELECT.*WHERE.*\$\{'),
                re.compile(r'["\']INSERT.*VALUES.*\{["\']'),
                re.compile(r'["\']UPDATE.*SET.*\{["\']'),
                re.compile(r'["\']DELETE.*WHERE.*\{["\']'),
            ],
            "xss": [
                re.compile(r'innerHTML\s*=\s*["\'].*["\']'),
                re.compile(r'document\.write\s*\('),
                re.compile(r'eval\s*\('),
            ],
            "hardcoded_secrets": [
                re.compile(r'(api_key|apikey|api-key|secret|password|token)\s*=\s*["\'][^"\']{8,}["\']'),
                re.compile(r'(bearer|authorization)\s*[:=]\s*["\'][^"\']{20,}["\']'),
            ],
            "console_log": [
                re.compile(r'console\.log\s*\('),
                re.compile(r'console\.debug\s*\('),
                re.compile(r'console\.warn\s*\('),
            ],
            "todo": [
                re.compile(r'TODO|FIXME|XXX|HACK'),
            ],
            "large_function": None,  # Needs line counting
            "complex_conditional": [
                re.compile(r'\s{8,}if\s*\(.+\s+&&\s+.+\s+&&\s+.+\)'),
                re.compile(r'\s{8,}if\s*\(.+\s+\|\|\s+.+\s+\|\|\s+.+\)'),
            ],
            "magic_number": [
                re.compile(r'\b\d{4,}\b'),  # Numbers with 4+ digits
                re.compile(r'\b\d+\.\d{4,}\b'),  # Floats with 4+ decimal places
            ],
        }
    
    def parse_diff(self, diff: str) -> List[DiffHunk]:
        """Parse git diff into hunks."""
        hunks = []
        current_hunk = None
        line_number = 0
        
        for line in diff.split('\n'):
            # New file
            if line.startswith('+++ b/'):
                file_path = line[6:]
                line_number = 0
                continue
            
            # New hunk
            if line.startswith('@@'):
                match = re.search(r'@@ -\d+,\d+ \+(\d+)', line)
                if match:
                    line_number = int(match.group(1))
                    current_hunk = DiffHunk(file_path, line_number, [], [], [])
                    hunks.append(current_hunk)
                continue
            
            if not current_hunk:
                continue
            
            current_hunk.lines.append(line)
            
            # Added line
            if line.startswith('+'):
                code = line[1:]
                current_hunk.added_lines.append((line_number, code))
                line_number += 1
            # Removed line
            elif line.startswith('-'):
                code = line[1:]
                current_hunk.removed_lines.append((line_number, code))
            # Context line
            elif not line.startswith('\\'):
                line_number += 1
        
        return hunks
    
    def analyze_file(self, file_path: str, hunks: List[DiffHunk]) -> List[ConventionalComment]:
        """Analyze all hunks in a file."""
        comments = []
        
        for hunk in hunks:
            if hunk.file_path != file_path:
                continue
            
            comments.extend(self._analyze_hunk(hunk))
        
        return comments
    
    def _analyze_hunk(self, hunk: DiffHunk) -> List[ConventionalComment]:
        """Analyze a single diff hunk."""
        comments = []
        
        for line_number, code in hunk.added_lines:
            # Skip comments and whitespace
            stripped = code.strip()
            if not stripped or stripped.startswith('//') or stripped.startswith('#') or stripped.startswith('*'):
                continue
            
            # Check for security issues
            comments.extend(self._check_security(hunk, line_number, code))
            
            # Check for code quality issues
            comments.extend(self._check_quality(hunk, line_number, code))
            
            # Check for todos
            comments.extend(self._check_todos(hunk, line_number, code))
        
        return comments
    
    def _check_security(self, hunk: DiffHunk, line_number: int, code: str) -> List[ConventionalComment]:
        """Check for security vulnerabilities."""
        comments = []
        
        # SQL injection
        for pattern in self.patterns["sql_injection"]:
            if pattern.search(code):
                comments.append(ConventionalComment(
                    label=Label.ISSUE,
                    subject=f"SQL injection vulnerability",
                    decorations=[Decoration.SECURITY, Decoration.BLOCKING],
                    discussion=f"Line {line_number}: This directly interpolates user input into SQL. Use parameterized queries instead.",
                    file_path=hunk.file_path,
                    line=line_number
                ))
                break
        
        # XSS
        for pattern in self.patterns["xss"]:
            if pattern.search(code):
                comments.append(ConventionalComment(
                    label=Label.ISSUE,
                    subject=f"XSS vulnerability",
                    decorations=[Decoration.SECURITY],
                    discussion=f"Line {line_number}: Setting HTML directly from untrusted input can lead to XSS. Use proper escaping or text content.",
                    file_path=hunk.file_path,
                    line=line_number
                ))
                break
        
        # Hardcoded secrets
        for pattern in self.patterns["hardcoded_secrets"]:
            match = pattern.search(code)
            if match:
                comments.append(ConventionalComment(
                    label=Label.ISSUE,
                    subject=f"Hardcoded secret detected",
                    decorations=[Decoration.SECURITY, Decoration.BLOCKING],
                    discussion=f"Line {line_number}: {match.group(1)} appears to be hardcoded. Move to environment variables or secret management.",
                    file_path=hunk.file_path,
                    line=line_number
                ))
                break
        
        return comments
    
    def _check_quality(self, hunk: DiffHunk, line_number: int, code: str) -> List[ConventionalComment]:
        """Check for code quality issues."""
        comments = []
        
        # Console logs
        for pattern in self.patterns["console_log"]:
            if pattern.search(code):
                comments.append(ConventionalComment(
                    label=Label.NITPICK,
                    subject=f"Debug console statement",
                    decorations=[Decoration.NON_BLOCKING],
                    discussion=f"Line {line_number}: Remove console.log before merging.",
                    file_path=hunk.file_path,
                    line=line_number
                ))
                break
        
        # Complex conditionals
        for pattern in self.patterns["complex_conditional"]:
            if pattern.search(code):
                comments.append(ConventionalComment(
                    label=Label.SUGGESTION,
                    subject=f"Complex conditional - consider extracting",
                    decorations=[Decoration.READABILITY, Decoration.NON_BLOCKING],
                    discussion=f"Line {line_number}: This conditional is complex. Consider extracting to a helper function or variable for clarity.",
                    file_path=hunk.file_path,
                    line=line_number
                ))
                break
        
        # Magic numbers
        for pattern in self.patterns["magic_number"]:
            match = pattern.search(code)
            if match and match.group(0) not in ['1000', '60', '3600']:  # Common constants
                comments.append(ConventionalComment(
                    label=Label.NITPICK,
                    subject=f"Magic number: {match.group(0)}",
                    decorations=[Decoration.READABILITY, Decoration.NON_BLOCKING],
                    discussion=f"Line {line_number}: Consider using a named constant instead of this magic number.",
                    file_path=hunk.file_path,
                    line=line_number
                ))
                break
        
        return comments
    
    def _check_todos(self, hunk: DiffHunk, line_number: int, code: str) -> List[ConventionalComment]:
        """Check for TODOs that should be addressed."""
        comments = []
        
        for pattern in self.patterns["todo"]:
            match = pattern.search(code)
            if match:
                comments.append(ConventionalComment(
                    label=Label.TODO,
                    subject=f"TODO found in code",
                    decorations=[],
                    discussion=f"Line {line_number}: {code.strip()} - Address this before or after merging.",
                    file_path=hunk.file_path,
                    line=line_number
                ))
                break
        
        return comments
    
    def check_verification_criterion(self, criterion: str, diff: str, files: List[Dict]) -> str:
        """Check if a single verification criterion is met by the diff.

        Returns: "pass", "fail", or "unknown"
        """
        criterion_lower = criterion.lower()

        # Pattern: "endpoint X exists" or "new endpoint" or "route"
        endpoint_match = re.search(r'endpoint\s+[`"\']?((?:GET|POST|PUT|DELETE|PATCH)\s+)?(/\S+)', criterion, re.IGNORECASE)
        if endpoint_match:
            route_path = endpoint_match.group(2).strip('`"\'')
            # Check if route appears in added lines
            if re.search(re.escape(route_path), diff):
                return "pass"
            return "fail"

        # Pattern: "uses logger" / "not console.log"
        if "logger" in criterion_lower and "console" in criterion_lower:
            hunks = self.parse_diff(diff)
            has_console = False
            for hunk in hunks:
                for _, code in hunk.added_lines:
                    if re.search(r'console\.(log|error|warn)\s*\(', code):
                        has_console = True
                        break
            return "fail" if has_console else "pass"

        # Pattern: "uses API_BASE_URL" / "${API_BASE_URL}"
        if "api_base_url" in criterion_lower:
            hunks = self.parse_diff(diff)
            has_relative_api = False
            has_any_fetch = False
            for hunk in hunks:
                for _, code in hunk.added_lines:
                    if re.search(r'fetch\s*\(', code):
                        has_any_fetch = True
                        if re.search(r'fetch\s*\(["\']/', code) and "API_BASE_URL" not in code:
                            has_relative_api = True
            if not has_any_fetch:
                return "pass"  # No fetch calls, criterion not applicable
            return "fail" if has_relative_api else "pass"

        # Pattern: "tests added" / "test coverage"
        if "test" in criterion_lower and ("added" in criterion_lower or "coverage" in criterion_lower):
            for file in files:
                path = file.get("path", "").lower()
                if "test" in path or "spec" in path:
                    return "pass"
            return "fail"

        # Pattern: "returns X status code" / "HTTP status"
        status_match = re.search(r'(?:status\s+code|HTTP)\s*(?:codes?)?\s*\(?([\d,\s]+)\)?', criterion, re.IGNORECASE)
        if status_match:
            codes = re.findall(r'\d{3}', status_match.group(1))
            if codes:
                found_any = any(code in diff for code in codes)
                return "pass" if found_any else "unknown"

        # Pattern: "error handling" / "try/catch"
        if "error handling" in criterion_lower:
            if re.search(r'(try\s*\{|except\s+|\.catch\s*\(|catch\s*\()', diff):
                return "pass"
            return "unknown"

        # Pattern: "sentry" tracking
        if "sentry" in criterion_lower:
            if re.search(r'Sentry\.|captureException|captureMessage|log_error', diff):
                return "pass"
            # Only fail if there are error paths without Sentry
            if re.search(r'(catch|except|\.catch)', diff):
                return "fail"
            return "unknown"

        # Generic: check if key terms from criterion appear in diff
        # Extract meaningful words (skip common words)
        skip_words = {'the', 'a', 'an', 'is', 'are', 'for', 'and', 'or', 'not', 'no',
                       'new', 'uses', 'should', 'must', 'with', 'from', 'into', 'that',
                       'this', 'have', 'has', 'been', 'added', 'exists', 'properly'}
        words = re.findall(r'[a-zA-Z_]\w{2,}', criterion)
        key_words = [w for w in words if w.lower() not in skip_words]

        if key_words:
            matches = sum(1 for w in key_words if w.lower() in diff.lower())
            ratio = matches / len(key_words)
            if ratio >= 0.5:
                return "pass"

        return "unknown"

    def analyze_complexity(self, diff: str, files: List[Dict]) -> Dict[str, any]:
        """Analyze PR complexity for split suggestions."""
        result = {
            "should_split": False,
            "reasons": [],
            "suggested_splits": []
        }
        
        # Check for multiple file types
        file_types = set()
        for file in files:
            if file.get("path"):
                ext = file["path"].split(".")[-1]
                file_types.add(ext)
        
        if len(file_types) > 3:
            result["should_split"] = True
            result["reasons"].append(f"Multiple file types: {', '.join(file_types)}")
        
        # Check for large number of files
        if len(files) > 15:
            result["should_split"] = True
            result["reasons"].append(f"Many files changed: {len(files)}")
        
        # Check for multiple logical areas
        areas = set()
        for file in files:
            path = file.get("path", "")
            if "test" in path.lower():
                areas.add("tests")
            elif "api" in path.lower() or "server" in path.lower():
                areas.add("backend")
            elif "client" in path.lower() or "web" in path.lower() or "ui" in path.lower():
                areas.add("frontend")
            elif "db" in path.lower() or "schema" in path.lower() or "migration" in path.lower():
                areas.add("database")
            elif "util" in path.lower() or "helper" in path.lower() or "lib" in path.lower():
                areas.add("utils")
        
        if len(areas) > 2:
            result["should_split"] = True
            result["reasons"].append(f"Multiple logical areas: {', '.join(areas)}")
            
            # Suggest splits based on areas
            if "database" in areas:
                result["suggested_splits"].append("Database/schema changes")
            if "backend" in areas:
                result["suggested_splits"].append("Backend API changes")
            if "frontend" in areas:
                result["suggested_splits"].append("Frontend/UI changes")
            if "utils" in areas:
                result["suggested_splits"].append("Utility/helper changes")
        
        # Parse diff for large functions
        hunks = self.parse_diff(diff)
        for hunk in hunks:
            func_lines = 0
            for line in hunk.added_lines:
                if "function" in line[1] or "def " in line[1]:
                    func_lines = 0
                func_lines += 1
                if func_lines > 30:
                    result["should_split"] = True
                    result["reasons"].append(f"Large function detected in {hunk.file_path}")
                    break
        
        return result
