// Generated from Atlas's real mobile endpoints (src/atlas/mobile_platform.py) with sample data,
// so these tests decode exactly what the server sends. Regenerate after changing the backend's shapes.
let atlasFixtures = ##"""
{
 "dashboard": {
  "read_id": "dashboard:1793746404343",
  "source": "dashboard",
  "data": {
   "areas": [
    {
     "about": "chores, repairs, cleaning, garden, furniture, household supplies",
     "color": "cocoa",
     "hex": "#795548",
     "icon": "🏠",
     "key": "home",
     "label": "Home"
    },
    {
     "about": "life admin: subscriptions, accounts, deliveries, returns, paperwork, phones, documents",
     "color": "sage",
     "hex": "#33b679",
     "icon": "📋",
     "key": "admin",
     "label": "Admin"
    },
    {
     "about": "tax, ISA, investments, bills, payments, banking",
     "color": "graphite",
     "hex": "#616161",
     "icon": "💷",
     "key": "finances",
     "label": "Finances"
    },
    {
     "about": "doctor, dentist, eyes, medicine, gym, training, diet, supplements",
     "color": "banana",
     "hex": "#f6bf26",
     "icon": "🩺",
     "key": "health",
     "label": "Health & Training"
    },
    {
     "about": "friends, family, dating, gifts, events with people, visits",
     "color": "tangerine",
     "hex": "#f4511e",
     "icon": "👥",
     "key": "social",
     "label": "Friends & Social"
    },
    {
     "about": "job, interviews, CV, professional learning",
     "color": "blueberry",
     "hex": "#3f51b5",
     "icon": "💼",
     "key": "career",
     "label": "Career"
    },
    {
     "about": "apps, coding projects, hustles, creative projects",
     "color": "lavender",
     "hex": "#7986cb",
     "icon": "🛠️",
     "key": "projects",
     "label": "Side Projects"
    },
    {
     "about": "big-picture aims, values, where life is heading, travel plans, learning for its own sake",
     "color": "eucalyptus",
     "hex": "#009688",
     "icon": "🧭",
     "key": "direction",
     "label": "Life Direction"
    }
   ],
   "captures": [
    {
     "actions": [
      {
       "area": null,
       "cadence_days": null,
       "due_at": null,
       "end_at": null,
       "event_kind": null,
       "item_id": null,
       "item_type": null,
       "kind": "inbox",
       "must": null,
       "must_why": null,
       "option": null,
       "pending_id": null,
       "plan_on": null,
       "project_id": null,
       "remind_at": null,
       "shopping_control": null,
       "start_at": null,
       "text": "remember milk",
       "title": null
      }
     ],
     "applied": [
      {
       "item_id": "fe0ebc8b92314c8e99bc",
       "op": "create"
      }
     ],
     "device_actions": [],
     "error": null,
     "id": "0999b9bb12d145458c87",
     "late_night": false,
     "raw_text": "remember milk",
     "received_at": "2026-11-03T22:53:24+00:00",
     "status": "ok",
     "summary": "📥 Inbox: remember milk",
     "tz": "Europe/London"
    }
   ],
   "closed_projects": [],
   "colors": {
    "important": "#ad1457",
    "kinds": {
     "date": "#e67c73",
     "family": "#039be5",
     "night_out": "#8e24aa",
     "routine": "#0b8043"
    },
    "urgent": "#d50000"
   },
   "day_ends": null,
   "days": [
    {
     "date": "2026-11-03",
     "leftovers": [],
     "overdue": [],
     "tasks": [
      {
       "area": "health",
       "capture_id": null,
       "created_at": "2026-11-03T22:53:24+00:00",
       "days_since_touch": 3.970914351851851e-06,
       "due_day": "2030-01-01",
       "id": "2caf6209feae411e91d6",
       "last_touched_at": "2026-11-03T22:53:24+00:00",
       "mentions": 1,
       "must": true,
       "must_why": "you marked it",
       "notes": [
        {
         "at": "2026-11-03T22:53:24+00:00",
         "capture_id": null,
         "text": "Ask about the filling"
        }
       ],
       "overdue": false,
       "phone": "pending",
       "pinned": false,
       "plan_day": "2026-11-03",
       "put_off_days": 3.970914351851851e-06,
       "remind_at": "2030-01-01T09:00:00+00:00",
       "source": "manual",
       "stage": "fresh",
       "status": "active",
       "title": "Book the dentist",
       "type": "todo"
      }
     ],
     "timed": []
    },
    {
     "date": "2026-11-04",
     "tasks": [],
     "timed": []
    }
   ],
   "done": [],
   "focus": [
    {
     "area": "health",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": "2030-01-01",
     "id": "2caf6209feae411e91d6",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": true,
     "must_why": "you marked it",
     "notes": [
      {
       "at": "2026-11-03T22:53:24+00:00",
       "capture_id": null,
       "text": "Ask about the filling"
      }
     ],
     "overdue": false,
     "phone": "pending",
     "pinned": false,
     "plan_day": "2026-11-03",
     "put_off_days": 3.970914351851851e-06,
     "remind_at": "2030-01-01T09:00:00+00:00",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Book the dentist",
     "type": "todo"
    }
   ],
   "goals": [
    {
     "area": "health",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "id": "6debaa54de9842ba9d2c",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "pinned": false,
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Run a half marathon",
     "type": "goal"
    }
   ],
   "habits": [
    {
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "id": "4746f86c98d44d748995",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "notes": [],
     "pinned": false,
     "source": "manual",
     "status": "active",
     "title": "Read more",
     "type": "habit"
    }
   ],
   "inbox": [
    {
     "created_at": "2026-10-01T10:00:00+00:00",
     "days_since_touch": 33.537087304247684,
     "id": "239e1df3609e4c888e60",
     "last_touched_at": "2026-10-01T10:00:00+00:00",
     "notes": [],
     "status": "active",
     "suggested_area": "finances",
     "suggested_title": "Sort out the ISA",
     "suggested_type": "todo",
     "title": "old note about ISA",
     "type": "inbox"
    },
    {
     "capture_id": "0999b9bb12d145458c87",
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "id": "fe0ebc8b92314c8e99bc",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "notes": [],
     "pinned": false,
     "source": "capture",
     "status": "active",
     "title": "remember milk",
     "type": "inbox"
    }
   ],
   "now": "2026-11-03T22:53:24.343087+00:00",
   "people": [
    {
     "cadence_days": 30,
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_contact": 3.970914351851851e-06,
     "days_since_touch": 3.970914351851851e-06,
     "id": "03376858fe084a378984",
     "last_contact_at": "2026-11-03T22:53:24+00:00",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "notes": [],
     "overdue_days": -29.999996029085647,
     "pinned": false,
     "source": "manual",
     "status": "active",
     "title": "Priya",
     "type": "person"
    }
   ],
   "planning": [
    {
     "area": "health",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": "2030-01-01",
     "id": "2caf6209feae411e91d6",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": true,
     "must_why": "you marked it",
     "notes": [
      {
       "at": "2026-11-03T22:53:24+00:00",
       "capture_id": null,
       "text": "Ask about the filling"
      }
     ],
     "overdue": false,
     "phone": "pending",
     "pinned": false,
     "plan_day": "2026-11-03",
     "put_off_days": 3.970914351851851e-06,
     "remind_at": "2030-01-01T09:00:00+00:00",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Book the dentist",
     "type": "todo"
    },
    {
     "area": "home",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": null,
     "id": "732d2def77034c299231",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "overdue": false,
     "pinned": false,
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Fix the cabinet door",
     "type": "todo"
    },
    {
     "cadence_days": 30,
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_contact": 3.970914351851851e-06,
     "days_since_touch": 3.970914351851851e-06,
     "id": "03376858fe084a378984",
     "last_contact_at": "2026-11-03T22:53:24+00:00",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "notes": [],
     "overdue_days": -29.999996029085647,
     "pinned": false,
     "source": "manual",
     "status": "active",
     "title": "Priya",
     "type": "person"
    },
    {
     "area": "projects",
     "board_column": "doing",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": null,
     "id": "aa012132c47548cfaa0b",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "overdue": false,
     "pinned": false,
     "project_id": "28e908b02e7a442a83a2",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Sketch the beds",
     "type": "todo"
    },
    {
     "area": "health",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "id": "6debaa54de9842ba9d2c",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "pinned": false,
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Run a half marathon",
     "type": "goal"
    }
   ],
   "project_work": [
    {
     "area": "projects",
     "board_column": "doing",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": null,
     "id": "aa012132c47548cfaa0b",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "overdue": false,
     "pinned": false,
     "project_id": "28e908b02e7a442a83a2",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Sketch the beds",
     "type": "todo"
    }
   ],
   "projects": [
    {
     "active_at": "2026-11-03T22:53:24+00:00",
     "capture_id": null,
     "counts": {
      "blocked": 0,
      "doing": 1,
      "done": 0,
      "ideas": 1,
      "todos": 1
     },
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "id": "28e908b02e7a442a83a2",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "link": null,
     "next": "Sketch the beds",
     "notes": [],
     "phase": "active",
     "pinned": false,
     "rank": -1,
     "repo": null,
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Garden app",
     "type": "project"
    }
   ],
   "refile": [],
   "today": "2026-11-03",
   "todos": [
    {
     "area": "health",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": "2030-01-01",
     "id": "2caf6209feae411e91d6",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": true,
     "must_why": "you marked it",
     "notes": [
      {
       "at": "2026-11-03T22:53:24+00:00",
       "capture_id": null,
       "text": "Ask about the filling"
      }
     ],
     "overdue": false,
     "phone": "pending",
     "pinned": false,
     "plan_day": "2026-11-03",
     "put_off_days": 3.970914351851851e-06,
     "remind_at": "2030-01-01T09:00:00+00:00",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Book the dentist",
     "type": "todo"
    },
    {
     "area": "home",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": null,
     "id": "732d2def77034c299231",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "overdue": false,
     "pinned": false,
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Fix the cabinet door",
     "type": "todo"
    }
   ],
   "tz": "Europe/London",
   "upcoming": [],
   "waiting": [
    {
     "expires_at": "2026-11-03T22:56:24+00:00",
     "handler": "shopping",
     "id": "5893e1b9d63c48fcb72c",
     "kind": "question",
     "options": [
      "Warburtons Protein Power",
      "Fitbakes bagels"
     ],
     "question": "Warburtons Protein Power or Fitbakes bagels?",
     "run_at": null,
     "summary": null
    }
   ],
   "warnings": []
  },
  "revision": "ea93ddefb02d0cef",
  "verified_at": "2026-11-03T22:53:24+00:00",
  "age_seconds": 0,
  "freshness": "fresh",
  "refreshing": false,
  "error": null
 },
 "today": {
  "read_id": "items:1793746404346",
  "source": "items",
  "data": {
   "date": "2026-11-03",
   "day_ends": null,
   "leftovers": [],
   "overdue": [],
   "tasks": [
    {
     "area": "health",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 3.970914351851851e-06,
     "due_day": "2030-01-01",
     "id": "2caf6209feae411e91d6",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": true,
     "must_why": "you marked it",
     "notes": [
      {
       "at": "2026-11-03T22:53:24+00:00",
       "capture_id": null,
       "text": "Ask about the filling"
      }
     ],
     "overdue": false,
     "phone": "pending",
     "pinned": false,
     "plan_day": "2026-11-03",
     "put_off_days": 3.970914351851851e-06,
     "remind_at": "2030-01-01T09:00:00+00:00",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Book the dentist",
     "type": "todo"
    }
   ],
   "timed": [],
   "today": "2026-11-03",
   "tomorrow": {
    "date": "2026-11-04",
    "tasks": [],
    "timed": []
   }
  },
  "revision": "f2668ab258f28510",
  "verified_at": "2026-11-03T22:53:24+00:00",
  "age_seconds": 0,
  "freshness": "fresh",
  "refreshing": false,
  "error": null
 },
 "all": {
  "read_id": "items:1793746404347",
  "source": "items",
  "data": [
   {
    "area": "health",
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "2caf6209feae411e91d6",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "mentions": 1,
    "must": true,
    "must_why": "you marked it",
    "note_count": 1,
    "notes": [
     {
      "at": "2026-11-03T22:53:24+00:00",
      "capture_id": null,
      "text": "Ask about the filling"
     }
    ],
    "overdue": false,
    "phone": "pending",
    "pinned": false,
    "plan_day": "2026-11-03",
    "remind_at": "2030-01-01T09:00:00+00:00",
    "source": "manual",
    "status": "active",
    "title": "Book the dentist",
    "type": "todo"
   },
   {
    "area": "home",
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "732d2def77034c299231",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "mentions": 1,
    "must": false,
    "must_why": null,
    "note_count": 0,
    "notes": [],
    "overdue": false,
    "pinned": false,
    "source": "manual",
    "status": "active",
    "title": "Fix the cabinet door",
    "type": "todo"
   },
   {
    "cadence_days": 30,
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "03376858fe084a378984",
    "last_contact_at": "2026-11-03T22:53:24+00:00",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "note_count": 0,
    "notes": [],
    "pinned": false,
    "source": "manual",
    "status": "active",
    "title": "Priya",
    "type": "person"
   },
   {
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "28e908b02e7a442a83a2",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "link": null,
    "note_count": 0,
    "notes": [],
    "phase": "active",
    "pinned": false,
    "rank": -1,
    "repo": null,
    "source": "manual",
    "status": "active",
    "title": "Garden app",
    "type": "project"
   },
   {
    "area": "projects",
    "board_column": "doing",
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "aa012132c47548cfaa0b",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "mentions": 1,
    "must": false,
    "must_why": null,
    "note_count": 0,
    "notes": [],
    "overdue": false,
    "pinned": false,
    "project_id": "28e908b02e7a442a83a2",
    "source": "manual",
    "status": "active",
    "title": "Sketch the beds",
    "type": "todo"
   },
   {
    "board_column": "ideas",
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "2a31941d2d7d40d2a7a2",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "mentions": 1,
    "note_count": 0,
    "notes": [],
    "pinned": false,
    "project_id": "28e908b02e7a442a83a2",
    "source": "manual",
    "status": "active",
    "title": "Watering reminders",
    "type": "idea"
   },
   {
    "area": "health",
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "6debaa54de9842ba9d2c",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "mentions": 1,
    "must": false,
    "must_why": null,
    "note_count": 0,
    "notes": [],
    "pinned": false,
    "source": "manual",
    "status": "active",
    "title": "Run a half marathon",
    "type": "goal"
   },
   {
    "capture_id": null,
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "4746f86c98d44d748995",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "note_count": 0,
    "notes": [],
    "pinned": false,
    "source": "manual",
    "status": "active",
    "title": "Read more",
    "type": "habit"
   },
   {
    "capture_id": "0999b9bb12d145458c87",
    "created_at": "2026-11-03T22:53:24+00:00",
    "id": "fe0ebc8b92314c8e99bc",
    "last_touched_at": "2026-11-03T22:53:24+00:00",
    "note_count": 0,
    "notes": [],
    "pinned": false,
    "source": "capture",
    "status": "active",
    "title": "remember milk",
    "type": "inbox"
   },
   {
    "created_at": "2026-10-01T10:00:00+00:00",
    "id": "239e1df3609e4c888e60",
    "last_touched_at": "2026-10-01T10:00:00+00:00",
    "note_count": 0,
    "notes": [],
    "status": "active",
    "suggested_area": "finances",
    "suggested_title": "Sort out the ISA",
    "suggested_type": "todo",
    "title": "old note about ISA",
    "type": "inbox"
   }
  ],
  "revision": "21b11fe30a6f782b",
  "verified_at": "2026-11-03T22:53:24+00:00",
  "age_seconds": 0,
  "freshness": "fresh",
  "refreshing": false,
  "error": null
 },
 "project": {
  "read_id": "project:1793746404349",
  "source": "project",
  "data": {
   "active_at": "2026-11-03T22:53:24+00:00",
   "capture_id": null,
   "cards": [
    {
     "area": "projects",
     "board_column": "doing",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 0,
     "due_day": null,
     "id": "aa012132c47548cfaa0b",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "overdue": false,
     "pinned": false,
     "project_id": "28e908b02e7a442a83a2",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Sketch the beds",
     "type": "todo"
    },
    {
     "board_column": "ideas",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 0,
     "id": "2a31941d2d7d40d2a7a2",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "notes": [],
     "pinned": false,
     "project_id": "28e908b02e7a442a83a2",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Watering reminders",
     "type": "idea"
    }
   ],
   "counts": {
    "blocked": 0,
    "doing": 1,
    "done": 0,
    "ideas": 1,
    "todos": 1
   },
   "created_at": "2026-11-03T22:53:24+00:00",
   "days_since_touch": 4.043344907407408e-06,
   "done": [],
   "id": "28e908b02e7a442a83a2",
   "ideas": [
    {
     "board_column": "ideas",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 0,
     "id": "2a31941d2d7d40d2a7a2",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "notes": [],
     "pinned": false,
     "project_id": "28e908b02e7a442a83a2",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Watering reminders",
     "type": "idea"
    }
   ],
   "last_touched_at": "2026-11-03T22:53:24+00:00",
   "link": null,
   "next": "Sketch the beds",
   "notes": [],
   "phase": "active",
   "pinned": false,
   "rank": -1,
   "repo": null,
   "source": "manual",
   "stage": "fresh",
   "status": "active",
   "title": "Garden app",
   "todos": [
    {
     "area": "projects",
     "board_column": "doing",
     "capture_id": null,
     "created_at": "2026-11-03T22:53:24+00:00",
     "days_since_touch": 0,
     "due_day": null,
     "id": "aa012132c47548cfaa0b",
     "last_touched_at": "2026-11-03T22:53:24+00:00",
     "mentions": 1,
     "must": false,
     "must_why": null,
     "notes": [],
     "overdue": false,
     "pinned": false,
     "project_id": "28e908b02e7a442a83a2",
     "source": "manual",
     "stage": "fresh",
     "status": "active",
     "title": "Sketch the beds",
     "type": "todo"
    }
   ],
   "type": "project"
  },
  "revision": "6f6838d8bbe44d06",
  "verified_at": "2026-11-03T22:53:24+00:00",
  "age_seconds": 0,
  "freshness": "fresh",
  "refreshing": false,
  "error": null
 },
 "item": {
  "read_id": "item:1793746404350",
  "source": "item",
  "data": {
   "area": "health",
   "capture_id": null,
   "created_at": "2026-11-03T22:53:24+00:00",
   "id": "2caf6209feae411e91d6",
   "last_touched_at": "2026-11-03T22:53:24+00:00",
   "mentions": 1,
   "must": true,
   "must_why": "you marked it",
   "note_count": 1,
   "notes": [
    {
     "at": "2026-11-03T22:53:24+00:00",
     "capture_id": null,
     "text": "Ask about the filling"
    }
   ],
   "overdue": false,
   "phone": "pending",
   "pinned": false,
   "plan_day": "2026-11-03",
   "remind_at": "2030-01-01T09:00:00+00:00",
   "source": "manual",
   "status": "active",
   "title": "Book the dentist",
   "type": "todo"
  },
  "revision": "a70146985bcba47c",
  "verified_at": "2026-11-03T22:53:24+00:00",
  "age_seconds": 0,
  "freshness": "fresh",
  "refreshing": false,
  "error": null
 },
 "operation": {
  "kind": "action",
  "status": "completed",
  "title": "Update: Book the dentist",
  "text": "",
  "handler": "items.update",
  "input": {
   "item_id": "2caf6209feae411e91d6",
   "pinned": true
  },
  "tz": "Europe/London",
  "delay_seconds": 0,
  "execute_at": "2026-11-03T22:53:24.352144+00:00",
  "created_at": "2026-11-03T22:53:24.352149+00:00",
  "updated_at": "2026-11-03T22:53:24+00:00",
  "summary": "Pinned “Book the dentist”",
  "revision": 2,
  "result": {
   "item_id": "2caf6209feae411e91d6"
  },
  "id": "6de31b61-e2aa-4a25-addb-887d47cf54b9"
 }
}
"""##
