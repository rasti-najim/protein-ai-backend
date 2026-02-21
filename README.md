<h1 align="center">Protein AI — Backend</h1>

<p align="center">
  <strong>Supabase-powered backend for <a href="https://github.com/rasti-najim/protein-ai">Protein AI</a></strong><br/>
  Edge Functions, PostgreSQL schema, and real-time infrastructure for AI meal tracking.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Supabase-BaaS-3ECF8E?style=flat-square&logo=supabase" alt="Supabase" />
  <img src="https://img.shields.io/badge/Deno-Edge_Functions-000000?style=flat-square&logo=deno" alt="Deno" />
  <img src="https://img.shields.io/badge/PostgreSQL-Database-4169E1?style=flat-square&logo=postgresql" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/OpenAI-Vision_API-412991?style=flat-square&logo=openai" alt="OpenAI" />
</p>

<p align="center">
  <a href="#architecture">Architecture</a> &bull;
  <a href="#edge-functions">Edge Functions</a> &bull;
  <a href="#database-schema">Database Schema</a> &bull;
  <a href="#getting-started">Getting Started</a> &bull;
  <a href="https://github.com/rasti-najim/protein-ai">Frontend Repo</a>
</p>

---

## Architecture

This backend is entirely **serverless**, built on [Supabase](https://supabase.com):

```
┌─────────────────────────────────────────────────────┐
│                   Supabase Platform                  │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │    Auth       │  │   Storage    │  │ Real-time │ │
│  │  Google/Apple │  │  Temp photos │  │   Subs    │ │
│  └──────┬───────┘  └──────┬───────┘  └───────────┘ │
│         │                 │                         │
│  ┌──────▼─────────────────▼───────────────────────┐ │
│  │            Edge Functions (Deno)                │ │
│  │                                                 │ │
│  │  scan-photo  ──► OpenAI Vision ──► meal record  │ │
│  │  analyze-meal-description ──► OpenAI ──► result │ │
│  │  fetch-streak ──► streak data                   │ │
│  │  delete-account ──► cleanup                     │ │
│  │  streak-maintenance ──► recalculation           │ │
│  └──────────────────┬──────────────────────────────┘ │
│                     │                               │
│  ┌──────────────────▼──────────────────────────────┐ │
│  │          PostgreSQL Database                    │ │
│  │                                                 │ │
│  │  users  │  meals  │  streaks  │  views          │ │
│  │  RLS policies for multi-tenant isolation        │ │
│  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## Edge Functions

All serverless functions are written in **TypeScript** running on the **Deno** runtime.

### `scan-photo`
The core AI feature. Processes meal photos through OpenAI's vision model.

```
POST /functions/v1/scan-photo
Authorization: Bearer <user_jwt>
Body: { imagePath: "temp/photo-123.jpg" }
```

**Flow:** Authenticate user &rarr; Get signed URL from storage &rarr; Send to OpenAI Vision &rarr; Parse meal name + protein &rarr; Insert into `meals` table &rarr; Update streak &rarr; Clean up temp image &rarr; Return result

### `analyze-meal-description`
Text-based meal analysis for manual entry.

```
POST /functions/v1/analyze-meal-description
Authorization: Bearer <user_jwt>
Body: { description: "grilled chicken breast with rice" }
```

**Returns:** `{ meal_name: "Grilled Chicken & Rice", protein_amount: 42 }`

### `fetch-streak`
Returns the user's current and max streaks with daily history.

```
GET /functions/v1/fetch-streak
Authorization: Bearer <user_jwt>
```

**Returns:** `{ length, maxStreak, lastGoalDate, streakHistory[] }`

### `delete-account`
GDPR-compliant account deletion with full data cleanup.

### `streak-maintenance`
Scheduled function for periodic streak recalculation and edge case handling.

---

## Database Schema

### Tables

| Table | Description |
|-------|-------------|
| `users` | User profiles — daily protein target, gender, goal, exercise frequency, weight |
| `meals` | Logged meals — name, protein amount, timestamp, logging method (photo/manual) |
| `streak_levels` | Gamification tiers — name, threshold, emoji for each level |

### Views

| View | Purpose |
|------|---------|
| `user_streak_view` | Calculates current/max streaks with daily breakdown using window functions |
| `weekly_meals_view` | Aggregates daily protein totals by week for the progress chart |

### Enums

```sql
gender_type:             male | female | other
exercise_frequency_type: 0-2 | 3-4 | 5+
goal_type:               lose | maintain | gain
weight_unit_type:        kg | lbs
```

### Row Level Security

All tables enforce RLS policies — users can only read and modify their own data. Service role keys are used only in Edge Functions for admin operations.

---

## Migrations

The `supabase/migrations/` directory contains **34 migration files** tracking the full schema evolution:

```
20250109  Initial schema (users, meals, enums)
20250111  RLS policies + temp storage bucket
20250112  Streak view + weekly meals view
   ...
20250820  Redesigned streak system + logging method tracking
20250901  Timezone fixes + grace period logic
```

---

## Getting Started

### Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli)
- [Deno](https://deno.land/) (for Edge Function development)
- OpenAI API key

### Local Development

```bash
# Clone the repo
git clone https://github.com/rasti-najim/protein-ai-backend.git
cd protein-ai-backend

# Start local Supabase (requires Docker)
supabase start

# Apply migrations
supabase db reset

# Serve Edge Functions locally
supabase functions serve --env-file .env.local
```

### Environment Variables

```env
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
OPENAI_API_KEY=your_openai_key
```

### Deploying

```bash
# Push migrations to production
supabase db push

# Deploy all Edge Functions
supabase functions deploy
```

---

## Related

- [protein-ai](https://github.com/rasti-najim/protein-ai) — React Native/Expo mobile app (frontend)

---

<p align="center">
  Built by <a href="https://github.com/rasti-najim">Rasti Aldawoodi</a>
</p>
