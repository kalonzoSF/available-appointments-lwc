# Available Appointments LWC

A Lightning Web Component for Salesforce Field Service that allows technicians to find and self-assign available service appointments near their current location.

## Features

- GPS-based location detection
- Radius filtering (5-50 miles)
- Schedule-aware filtering (only shows appointments that fit in gaps between scheduled work)
- Skill matching (filters by Work Type skill requirements)
- Travel time estimation (haversine distance with road factor)
- List and map views
- Crew member back-on-site buffer support
- Self-assign with one tap

## Prerequisites

- Salesforce org with Field Service (FSL) enabled
- Service Resources, Territories, and Skills configured
- ServiceAppointment records with geocoded addresses (Latitude/Longitude populated)

## Components

| Component | Description |
|-----------|-------------|
| `availableAppointments` | LWC with list/map views, GPS, and filter controls |
| `AvailableAppointmentsController` | Apex controller handling resource context, appointment queries, skill matching, schedule fitting, and self-assignment |

## Deploy to an Org

```bash
sf project deploy start --source-dir force-app --target-org <your-org-alias>
```

## Usage

Add the component to any Lightning Record Page, App Page, Home Page, or use it as a Screen Action. The component automatically detects the current user's Service Resource and loads available appointments in their assigned territories.
