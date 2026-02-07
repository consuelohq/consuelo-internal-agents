# LibreChat React Artifacts

Build interactive React components directly in LibreChat's side panel. This is one of the most powerful features — use it constantly for demos, dashboards, calculators, and interactive tools.

## Overview

React artifacts render actual React components in a sandboxed environment with:
- Full JSX support
- Tailwind CSS for styling
- shadcn/ui components pre-installed
- React hooks (useState, useEffect, etc.)
- Real-time interactivity

## When to Use React Artifacts

**ALWAYS consider a React artifact when discussing:**

| Scenario | React Artifact Use |
|----------|-------------------|
| UI/UX ideas | Build the actual component |
| Data visualization | Interactive charts, dashboards |
| Calculators/tools | Working calculators, converters |
| Forms/interfaces | Input validation, multi-step flows |
| Prototypes | Clickable demos of features |
| Admin panels | CRUD interfaces, data tables |
| Configurators | Pricing calculators, product builders |
| Timers/counters | Working countdowns, progress trackers |
| Games | Simple interactive games |
| Surveys/wizards | Multi-step user flows |

**Don't wait to be asked** — proactively say:
> "Want me to build this as a working React component so you can interact with it?"

## Syntax

```
:::artifact{identifier="unique-name" type="application/vnd.react" title="Descriptive Title"}
```jsx
import { useState } from 'react';
import { Button, Card, Input } from '@/components/ui';

export default function ComponentName() {
  const [state, setState] = useState(initialValue);
  
  return (
    <div className="p-4">
      {/* Your JSX here */}
    </div>
  );
}
```
:::
```

## Available Imports

**React:**
```jsx
import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
```

**shadcn/ui Components:**
```jsx
import { 
  Button, Card, Input, Label, Select, 
  Tabs, Dialog, DropdownMenu, Badge,
  Table, Textarea, Switch, Checkbox,
  RadioGroup, Slider, Progress, Alert,
  Avatar, Separator, Skeleton, Tooltip
} from '@/components/ui';
```

**Icons:**
```jsx
import { 
  Search, Plus, Trash, Edit, Save, 
  Check, X, ChevronDown, Menu, Settings,
  User, Bell, Home, Calendar, Clock
} from 'lucide-react';
```

**Utilities:**
```jsx
import { cn } from '@/lib/utils';  // clsx + tailwind-merge
```

## Examples by Use Case

### 1. Interactive Calculator
```jsx
:::artifact{identifier="price-calculator" type="application/vnd.react" title="Pricing Calculator"}
```jsx
import { useState } from 'react';
import { Card, Button, Input, Label } from '@/components/ui';

export default function PriceCalculator() {
  const [users, setUsers] = useState(10);
  const [pricePerUser] = useState(29);
  
  const total = users * pricePerUser;
  
  return (
    <Card className="p-6 max-w-md">
      <h2 className="text-xl font-bold mb-4">Pricing Calculator</h2>
      <div className="space-y-4">
        <div>
          <Label>Number of Users</Label>
          <Input 
            type="number" 
            value={users} 
            onChange={(e) => setUsers(Number(e.target.value))}
          />
        </div>
        <div className="pt-4 border-t">
          <div className="flex justify-between text-lg">
            <span>Total per month:</span>
            <span className="font-bold">${total}</span>
          </div>
        </div>
      </div>
    </Card>
  );
}
```
:::
```

### 2. Data Table with Search
```jsx
:::artifact{identifier="contact-list" type="application/vnd.react" title="Contact Manager"}
```jsx
import { useState } from 'react';
import { Input, Table, Badge } from '@/components/ui';
import { Search } from 'lucide-react';

const contacts = [
  { id: 1, name: 'Alice', status: 'active', role: 'Admin' },
  { id: 2, name: 'Bob', status: 'inactive', role: 'User' },
  { id: 3, name: 'Carol', status: 'active', role: 'Editor' },
];

export default function ContactList() {
  const [search, setSearch] = useState('');
  
  const filtered = contacts.filter(c => 
    c.name.toLowerCase().includes(search.toLowerCase())
  );
  
  return (
    <div className="space-y-4">
      <div className="relative">
        <Search className="absolute left-3 top-2.5 w-4 h-4 text-gray-400" />
        <Input 
          placeholder="Search contacts..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="pl-10"
        />
      </div>
      <Table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Role</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map(c => (
            <tr key={c.id}>
              <td>{c.name}</td>
              <td>{c.role}</td>
              <td>
                <Badge variant={c.status === 'active' ? 'default' : 'secondary'}>
                  {c.status}
                </Badge>
              </td>
            </tr>
          ))}
        </tbody>
      </Table>
    </div>
  );
}
```
:::
```

### 3. Multi-Step Wizard
```jsx
:::artifact{identifier="setup-wizard" type="application/vnd.react" title="Setup Wizard"}
```jsx
import { useState } from 'react';
import { Button, Card, Progress } from '@/components/ui';

const steps = ['Account', 'Profile', 'Preferences', 'Complete'];

export default function SetupWizard() {
  const [currentStep, setCurrentStep] = useState(0);
  
  return (
    <Card className="p-6 max-w-lg">
      <Progress value={(currentStep + 1) / steps.length * 100} className="mb-4" />
      <div className="flex justify-between mb-6 text-sm">
        {steps.map((s, i) => (
          <span key={s} className={i === currentStep ? 'font-bold text-blue-600' : 'text-gray-400'}>
            {s}
          </span>
        ))}
      </div>
      <div className="py-8 text-center">
        <h3 className="text-lg font-semibold">Step {currentStep + 1}: {steps[currentStep]}</h3>
        <p className="text-gray-600 mt-2">Configure your {steps[currentStep].toLowerCase()} settings here.</p>
      </div>
      <div className="flex justify-between">
        <Button 
          variant="outline" 
          onClick={() => setCurrentStep(Math.max(0, currentStep - 1))}
          disabled={currentStep === 0}
        >
          Back
        </Button>
        <Button 
          onClick={() => setCurrentStep(Math.min(steps.length - 1, currentStep + 1))}
          disabled={currentStep === steps.length - 1}
        >
          Next
        </Button>
      </div>
    </Card>
  );
}
```
:::
```

### 4. Todo List (Full CRUD)
```jsx
:::artifact{identifier="todo-app" type="application/vnd.react" title="Todo List"}
```jsx
import { useState } from 'react';
import { Button, Input, Card, Checkbox } from '@/components/ui';
import { Plus, Trash } from 'lucide-react';

export default function TodoApp() {
  const [todos, setTodos] = useState([
    { id: 1, text: 'Learn React artifacts', done: false },
    { id: 2, text: 'Build cool stuff', done: true },
  ]);
  const [input, setInput] = useState('');
  
  const addTodo = () => {
    if (!input.trim()) return;
    setTodos([...todos, { id: Date.now(), text: input, done: false }]);
    setInput('');
  };
  
  const toggleTodo = (id) => {
    setTodos(todos.map(t => t.id === id ? { ...t, done: !t.done } : t));
  };
  
  const deleteTodo = (id) => {
    setTodos(todos.filter(t => t.id !== id));
  };
  
  return (
    <Card className="p-4 max-w-md">
      <h2 className="text-xl font-bold mb-4">Todo List</h2>
      <div className="flex gap-2 mb-4">
        <Input 
          value={input} 
          onChange={(e) => setInput(e.target.value)}
          placeholder="Add a task..."
          onKeyDown={(e) => e.key === 'Enter' && addTodo()}
        />
        <Button onClick={addTodo} size="icon"><Plus className="w-4 h-4" /></Button>
      </div>
      <div className="space-y-2">
        {todos.map(todo => (
          <div key={todo.id} className="flex items-center gap-2 p-2 bg-gray-50 rounded">
            <Checkbox checked={todo.done} onCheckedChange={() => toggleTodo(todo.id)} />
            <span className={todo.done ? 'line-through text-gray-400 flex-1' : 'flex-1'}>
              {todo.text}
            </span>
            <Button variant="ghost" size="icon" onClick={() => deleteTodo(todo.id)}>
              <Trash className="w-4 h-4 text-red-500" />
            </Button>
          </div>
        ))}
      </div>
    </Card>
  );
}
```
:::
```

### 5. Tabbed Interface
```jsx
:::artifact{identifier="tabbed-view" type="application/vnd.react" title="Tabbed Content"}
```jsx
import { useState } from 'react';
import { Tabs, TabsList, TabsTrigger, TabsContent, Card } from '@/components/ui';

export default function TabbedView() {
  return (
    <Tabs defaultValue="overview" className="w-full">
      <TabsList className="grid w-full grid-cols-3">
        <TabsTrigger value="overview">Overview</TabsTrigger>
        <TabsTrigger value="analytics">Analytics</TabsTrigger>
        <TabsTrigger value="settings">Settings</TabsTrigger>
      </TabsList>
      <TabsContent value="overview">
        <Card className="p-4">
          <h3 className="font-semibold mb-2">Overview Content</h3>
          <p className="text-gray-600">Your overview information goes here.</p>
        </Card>
      </TabsContent>
      <TabsContent value="analytics">
        <Card className="p-4">
          <h3 className="font-semibold mb-2">Analytics Content</h3>
          <p className="text-gray-600">Charts and data visualizations here.</p>
        </Card>
      </TabsContent>
      <TabsContent value="settings">
        <Card className="p-4">
          <h3 className="font-semibold mb-2">Settings Content</h3>
          <p className="text-gray-600">Configuration options here.</p>
        </Card>
      </TabsContent>
    </Tabs>
  );
}
```
:::
```

## Best Practices

1. **Always use `export default`** — required for the component to render
2. **Use Tailwind classes** — `className="p-4 bg-blue-50 rounded-lg"`
3. **Keep state simple** — useState is your friend
4. **Provide realistic data** — makes the demo feel real
5. **Add visual polish** — spacing, colors, hover states
6. **Handle empty states** — show friendly messages when no data
7. **Use proper types** — TypeScript is supported

## Common Patterns

### Loading State
```jsx
const [loading, setLoading] = useState(false);
// ...
{loading ? <Skeleton className="h-4 w-32" /> : <span>Data</span>}
```

### Form Validation
```jsx
const [error, setError] = useState('');
// ...
{error && <Alert variant="destructive">{error}</Alert>}
```

### Toggle Views
```jsx
const [view, setView] = useState('grid'); // 'grid' | 'list'
// ...
{view === 'grid' ? <GridView /> : <ListView />}
```

## Quick Templates

**Dashboard Card:**
```jsx
<Card className="p-6">
  <div className="flex items-center justify-between">
    <div>
      <p className="text-sm text-gray-600">Label</p>
      <p className="text-2xl font-bold">Value</p>
    </div>
    <Icon className="w-8 h-8 text-blue-500" />
  </div>
</Card>
```

**Form Layout:**
```jsx
<div className="space-y-4">
  <div>
    <Label>Field Name</Label>
    <Input placeholder="Enter value..." />
  </div>
  <Button>Submit</Button>
</div>
```

**List with Actions:**
```jsx
<div className="space-y-2">
  {items.map(item => (
    <div key={item.id} className="flex items-center justify-between p-3 bg-gray-50 rounded">
      <span>{item.name}</span>
      <div className="flex gap-2">
        <Button size="sm" variant="ghost">Edit</Button>
        <Button size="sm" variant="ghost" className="text-red-500">Delete</Button>
      </div>
    </div>
  ))}
</div>
```

## Proactive Triggers

**Build a React component when Ko mentions:**
- "I need a dashboard for..."
- "What would this UI look like?"
- "Can you calculate..."
- "I want to show users..."
- "How would this flow work?"
- "Build me a tool for..."
- "I need to track..."
- "What if we had a..."

**Examples:**
- "Working on pricing" → Build pricing calculator
- "Need a task tracker" → Build todo app
- "User onboarding" → Build multi-step wizard
- "Show me the data" → Build data table with search
- "Settings page" → Build tabbed settings interface

## Remember

**React artifacts are live code** — not mockups. Build things Ko can actually click, type into, and interact with. The more interactive, the better.
