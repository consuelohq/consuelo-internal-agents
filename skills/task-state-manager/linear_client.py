"""
Linear API Client for Task State Manager.

Uses Linear GraphQL API to create/update issues in the "Suelo Tasks" project.
"""
import os
import requests
from typing import Dict, Optional, List

class LinearClient:
    """
    Client for Linear GraphQL API.
    """
    
    API_URL = "https://api.linear.app/graphql"
    
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.getenv("LINEAR_API_KEY")
        if not self.api_key:
            raise ValueError("LINEAR_API_KEY not set")
        
        # Project IDs for Suelo Tasks (hardcoded for consuelo workspace)
        self.team_id = "29f5c661-da6c-4bfb-bd48-815a006ccaac"
        self.project_id = "4ad23224-d294-42ac-a9c4-1f4ac943f6e3"
        
        self.headers = {
            "Authorization": self.api_key,
            "Content-Type": "application/json"
        }
    
    def query(self, query: str, variables: Optional[Dict] = None) -> Dict:
        """Execute GraphQL query."""
        response = requests.post(
            self.API_URL,
            headers=self.headers,
            json={"query": query, "variables": variables or {}}
        )
        response.raise_for_status()
        return response.json()
    
    def create_issue(
        self,
        title: str,
        description: str,
        state_name: str = "In Progress",
        label: Optional[str] = "suelo-task"
    ) -> Dict:
        """
        Create a new issue in the Suelo Tasks project.
        """
        mutation = """
        mutation IssueCreate($input: IssueCreateInput!) {
            issueCreate(input: $input) {
                success
                issue {
                    id
                    identifier
                    title
                    url
                    state {
                        name
                    }
                }
            }
        }
        """
        
        input_data = {
            "title": f"[Suelo] {title}",
            "description": description,
            "teamId": self.team_id,
            "projectId": self.project_id
        }
        
        if state_name:
            input_data["stateId"] = self._get_state_id(state_name)
        
        variables = {"input": input_data}
        
        result = self.query(mutation, variables)
        
        if result.get("errors"):
            raise Exception(f"Linear API error: {result['errors']}")
        
        return result["data"]["issueCreate"]["issue"]
    
    def update_issue(
        self,
        issue_id: str,
        description_update: Optional[str] = None,
        state_name: Optional[str] = None
    ) -> Dict:
        """
        Update an existing issue with progress.
        """
        mutation = """
        mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
            issueUpdate(id: $id, input: $input) {
                success
                issue {
                    id
                    identifier
                    title
                    description
                }
            }
        }
        """
        
        input_data = {}
        if description_update:
            input_data["description"] = description_update
        if state_name:
            input_data["stateId"] = self._get_state_id(state_name)
        
        variables = {
            "id": issue_id,
            "input": input_data
        }
        
        result = self.query(mutation, variables)
        return result["data"]["issueUpdate"]["issue"]
    
    def get_active_issues(self) -> List[Dict]:
        """
        Get all issues in "In Progress" state for the Suelo Tasks project.
        """
        query = """
        query GetProjectIssues($projectId: ID!) {
            project(id: $projectId) {
                issues(states: {name: {eq: "In Progress"}}) {
                    nodes {
                        id
                        identifier
                        title
                        description
                        state {
                            name
                        }
                        createdAt
                        updatedAt
                    }
                }
            }
        }
        """
        
        variables = {"projectId": self.project_id}
        result = self.query(query, variables)
        
        return result["data"]["project"]["issues"]["nodes"]
    
    def _get_state_id(self, state_name: str) -> Optional[str]:
        """
        Get state ID from name.
        Cache this to avoid repeated lookups.
        """
        # TODO: Implement state ID caching
        # For now, query every time
        query = """
        query GetTeamStates($teamId: String!) {
            team(id: $teamId) {
                states {
                    nodes {
                        id
                        name
                    }
                }
            }
        }
        """
        
        result = self.query(query, {"teamId": self.team_id})
        states = result["data"]["team"]["states"]["nodes"]
        
        for state in states:
            if state["name"] == state_name:
                return state["id"]
        
        return None
    
    def setup_project(self, project_name: str = "Suelo Tasks") -> Dict:
        """
        One-time setup to create the Suelo Tasks project.
        Run this once to get project ID.
        """
        # Create project
        mutation = """
        mutation ProjectCreate($input: ProjectCreateInput!) {
            projectCreate(input: $input) {
                success
                project {
                    id
                    name
                    url
                }
            }
        }
        """
        
        variables = {
            "input": {
                "name": project_name,
                "teamIds": [self.team_id],
                "description": "Personal task tracking for Suelo AI assistant"
            }
        }
        
        result = self.query(mutation, variables)
        return result["data"]["projectCreate"]["project"]
