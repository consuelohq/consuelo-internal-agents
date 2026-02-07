"""Conventional Comments formatting."""

from typing import List, Optional
from dataclasses import dataclass
from enum import Enum


class Label(Enum):
    """Conventional comment labels."""
    PRAISE = "praise"
    NITPICK = "nitpick"
    SUGGESTION = "suggestion"
    ISSUE = "issue"
    TODO = "todo"
    QUESTION = "question"
    THOUGHT = "thought"
    CHORE = "chore"
    NOTE = "note"


class Decoration(Enum):
    """Conventional comment decorations."""
    BLOCKING = "blocking"
    NON_BLOCKING = "non-blocking"
    SECURITY = "security"
    TEST = "test"
    IF_MINOR = "if-minor"
    READABILITY = "readability"
    MAINTAINABILITY = "maintainability"
    PERFORMANCE = "performance"
    UX = "ux"


@dataclass
class ConventionalComment:
    """A conventional comment."""
    label: Label
    subject: str
    decorations: List[Decoration] = None
    discussion: str = None
    file_path: str = None
    line: int = None
    code_snippet: str = None
    
    def __post_init__(self):
        if self.decorations is None:
            self.decorations = []
    
    def format_inline(self) -> str:
        """Format for inline comment on GitHub."""
        parts = [self.label.value]
        
        if self.decorations:
            dec_str = ",".join(d.value for d in self.decorations)
            parts.append(f"({dec_str})")
        
        line = f"{' '.join(parts)}: {self.subject}"
        
        if self.discussion:
            line += f"\n\n{self.discussion}"
        
        if self.code_snippet:
            line += f"\n\n```diff\n{self.code_snippet}\n```"
        
        return line
    
    def format_summary(self) -> str:
        """Format for review summary."""
        parts = [self.label.value]
        
        if self.decorations:
            dec_str = ",".join(d.value for d in self.decorations)
            parts.append(f"({dec_str})")
        
        line = f"- [{self.label.value}]"
        if self.decorations:
            line += f" ({','.join(d.value for d in self.decorations)})"
        line += f" {self.subject}"
        
        return line
    
    def is_blocking(self) -> bool:
        """Check if this is a blocking comment."""
        return Decoration.BLOCKING in self.decorations
    
    def is_non_blocking(self) -> bool:
        """Check if this is explicitly non-blocking."""
        return Decoration.NON_BLOCKING in self.decorations
    
    def is_security(self) -> bool:
        """Check if this is a security issue."""
        return Decoration.SECURITY in self.decorations


class ReviewSummary:
    """Organizes all comments into a review summary."""
    
    def __init__(self):
        self.comments: List[ConventionalComment] = []
        self.praise: List[ConventionalComment] = []
        self.nitpicks: List[ConventionalComment] = []
        self.suggestions: List[ConventionalComment] = []
        self.issues: List[ConventionalComment] = []
        self.todos: List[ConventionalComment] = []
        self.questions: List[ConventionalComment] = []
        self.thoughts: List[ConventionalComment] = []
    
    def add_comment(self, comment: ConventionalComment):
        """Add a comment and categorize it."""
        self.comments.append(comment)
        
        if comment.label == Label.PRAISE:
            self.praise.append(comment)
        elif comment.label == Label.NITPICK:
            self.nitpicks.append(comment)
        elif comment.label == Label.SUGGESTION:
            self.suggestions.append(comment)
        elif comment.label == Label.ISSUE:
            self.issues.append(comment)
        elif comment.label == Label.TODO:
            self.todos.append(comment)
        elif comment.label == Label.QUESTION:
            self.questions.append(comment)
        elif comment.label == Label.THOUGHT:
            self.thoughts.append(comment)
    
    def get_blocking_issues(self) -> List[ConventionalComment]:
        """Get all blocking issues."""
        return [c for c in self.issues if c.is_blocking()]
    
    def get_security_issues(self) -> List[ConventionalComment]:
        """Get all security issues."""
        return [c for c in self.comments if c.is_security()]
    
    def has_blocking(self) -> bool:
        """Check if there are any blocking issues."""
        return len(self.get_blocking_issues()) > 0
    
    def format(self, pr_size: int, description_ok: bool, tests_ok: bool) -> str:
        """Format the entire review summary."""
        lines = ["## Review Summary\n"]
        
        # PR metadata
        lines.append(f"**PR Size:** {pr_size} lines " + ("✓" if pr_size < 400 else "⚠️ (large)"))
        lines.append(f"**Description:** {'✓ includes context' if description_ok else '⚠️ needs context'}")
        lines.append(f"**Tests:** {'✓ added' if tests_ok else '⚠️ minimal or missing'}")
        lines.append("")
        
        # Blocking issues
        blocking = self.get_blocking_issues()
        if blocking:
            lines.append(f"### Blocking Issues ({len(blocking)})")
            for comment in blocking:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Security issues
        security = self.get_security_issues()
        if security:
            lines.append(f"### Security Issues ({len(security)})")
            for comment in security:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Issues (non-blocking)
        non_blocking_issues = [c for c in self.issues if not c.is_blocking()]
        if non_blocking_issues:
            lines.append(f"### Issues ({len(non_blocking_issues)})")
            for comment in non_blocking_issues:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Suggestions
        if self.suggestions:
            lines.append(f"### Suggestions ({len(self.suggestions)})")
            for comment in self.suggestions:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Questions
        if self.questions:
            lines.append(f"### Questions ({len(self.questions)})")
            for comment in self.questions:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Todos
        if self.todos:
            lines.append(f"### TODOs ({len(self.todos)})")
            for comment in self.todos:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Nitpicks
        if self.nitpicks:
            lines.append(f"### Nitpicks ({len(self.nitpicks)})")
            for comment in self.nitpicks:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Thoughts
        if self.thoughts:
            lines.append(f"### Thoughts ({len(self.thoughts)})")
            for comment in self.thoughts:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Praise (always good to end on a positive note)
        if self.praise:
            lines.append(f"### Praise ({len(self.praise)})")
            for comment in self.praise:
                lines.append(comment.format_summary())
            lines.append("")
        
        # Overall recommendation
        lines.append("---\n")
        if blocking or security:
            lines.append("**🚨 Recommendation:** Request changes - fix blocking issues")
        elif len(self.issues) > 3 or len(self.suggestions) > 5:
            lines.append("**⚠️ Recommendation:** Discuss - several issues to address")
        else:
            lines.append("**✅ Recommendation:** Approve - minor issues only")
        
        return "\n".join(lines)
