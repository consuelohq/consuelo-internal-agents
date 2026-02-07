"""Code review checklist generation and management."""

from typing import List, Dict, Optional
from enum import Enum


class ChecklistItem:
    """A single checklist item."""
    
    def __init__(self, category: str, text: str, checked: bool = False):
        self.category = category
        self.text = text
        self.checked = checked
        self.notes: List[str] = []
    
    def check(self, notes: Optional[str] = None):
        """Mark as checked."""
        self.checked = True
        if notes:
            self.notes.append(notes)
    
    def uncheck(self):
        """Mark as unchecked."""
        self.checked = False
    
    def add_note(self, note: str):
        """Add a note about this item."""
        self.notes.append(note)
    
    def format(self) -> str:
        """Format as GitHub task list item."""
        status = "x" if self.checked else " "
        line = f"- [{status}] {self.text}"
        
        if self.notes:
            for note in self.notes:
                line += f"\n  - {note}"
        
        return line


class ReviewChecklist:
    """Manages the complete code review checklist."""
    
    def __init__(self):
        self.items: List[ChecklistItem] = []
        
        # Initialize all checklist items
        self._initialize_items()
    
    def _initialize_items(self):
        """Create all checklist items."""
        categories = {
            "functionality": [
                "code performs as intended",
                "edge cases tested",
                "error handling verified",
                "inputs validated",
                "outputs correct for all cases"
            ],
            "readability": [
                "descriptive variable/function names",
                "consistent naming conventions",
                "well-documented with comments",
                "logical code organization",
                "no magic numbers/strings"
            ],
            "maintainability": [
                "modular functions (single responsibility)",
                "loose coupling between components",
                "design decisions documented",
                "no code duplication",
                "easy to extend or modify"
            ],
            "security": [
                "inputs sanitized/validated",
                "access controls checked",
                "no SQL injection vulnerabilities",
                "no XSS vulnerabilities",
                "sensitive data properly handled"
            ],
            "performance": [
                "efficient algorithms used",
                "no unnecessary database queries",
                "caching where appropriate",
                "no obvious bottlenecks",
                "memory usage reasonable"
            ],
            "coding standards": [
                "linter passes",
                "follows project conventions",
                "tests added for new code",
                "proper error handling",
                "consistent formatting"
            ]
        }
        
        for category, items in categories.items():
            for item_text in items:
                self.items.append(ChecklistItem(category, item_text))
    
    def get_items(self, category: Optional[str] = None) -> List[ChecklistItem]:
        """Get items, optionally filtered by category."""
        if category:
            return [item for item in self.items if item.category == category]
        return self.items
    
    def check(self, text: str, notes: Optional[str] = None):
        """Check an item by text."""
        for item in self.items:
            if item.text == text:
                item.check(notes)
                return
        raise ValueError(f"Item not found: {text}")
    
    def check_category(self, category: str):
        """Check all items in a category."""
        for item in self.items:
            if item.category == category:
                item.check()
    
    def uncheck(self, text: str):
        """Uncheck an item by text."""
        for item in self.items:
            if item.text == text:
                item.uncheck()
                return
        raise ValueError(f"Item not found: {text}")
    
    def add_note(self, text: str, note: str):
        """Add a note to an item."""
        for item in self.items:
            if item.text == text:
                item.add_note(note)
                return
        raise ValueError(f"Item not found: {text}")
    
    def is_complete(self) -> bool:
        """Check if all items are checked."""
        return all(item.checked for item in self.items)
    
    def get_unchecked(self) -> List[ChecklistItem]:
        """Get all unchecked items."""
        return [item for item in self.items if not item.checked]
    
    def get_progress(self) -> Dict[str, int]:
        """Get progress by category."""
        progress = {}
        
        for item in self.items:
            if item.category not in progress:
                progress[item.category] = {"total": 0, "checked": 0}
            
            progress[item.category]["total"] += 1
            if item.checked:
                progress[item.category]["checked"] += 1
        
        return progress
    
    def format(self) -> str:
        """Format as GitHub task list."""
        lines = ["## ✅ Code Review Checklist\n"]
        
        # Group by category
        categories = set(item.category for item in self.items)
        
        for category in sorted(categories):
            lines.append(f"\n### {category.capitalize()}")
            
            for item in self.items:
                if item.category == category:
                    lines.append(item.format())
        
        # Progress summary
        lines.append("\n---\n")
        progress = self.get_progress()
        total = sum(p["total"] for p in progress.values())
        checked = sum(p["checked"] for p in progress.values())
        percentage = int((checked / total) * 100) if total > 0 else 0
        
        lines.append(f"**Progress:** {checked}/{total} items checked ({percentage}%)")
        
        # Category breakdown
        lines.append("\n**By Category:**")
        for category, stats in sorted(progress.items()):
            cat_pct = int((stats["checked"] / stats["total"]) * 100) if stats["total"] > 0 else 0
            cat_status = "✓" if stats["checked"] == stats["total"] else "⚠️"
            lines.append(f"- {cat_status} {category}: {stats['checked']}/{stats['total']} ({cat_pct}%)")
        
        return "\n".join(lines)
    
    def format_for_ai(self) -> str:
        """Format for AI context (what's left to check)."""
        unchecked = self.get_unchecked()
        
        if not unchecked:
            return "✓ All checklist items complete"
        
        lines = ["## Remaining Checklist Items\n"]
        
        for category in sorted(set(item.category for item in unchecked)):
            lines.append(f"\n### {category.capitalize()}")
            for item in unchecked:
                if item.category == category:
                    lines.append(f"- [ ] {item.text}")
        
        return "\n".join(lines)
