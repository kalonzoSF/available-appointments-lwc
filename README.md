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
- Salesforce CLI (`sf`) installed — [Install Guide](https://developer.salesforce.com/tools/salesforcecli)
- Git installed

## Components

| Component | Description |
|-----------|-------------|
| `availableAppointments` | LWC with list/map views, GPS, and filter controls |
| `AvailableAppointmentsController` | Apex controller handling resource context, appointment queries, skill matching, schedule fitting, and self-assignment |

## Project Structure

```
available-appointments-lwc/
├── force-app/main/default/
│   ├── classes/
│   │   ├── AvailableAppointmentsController.cls
│   │   └── AvailableAppointmentsController.cls-meta.xml
│   └── lwc/
│       └── availableAppointments/
│           ├── availableAppointments.css
│           ├── availableAppointments.html
│           ├── availableAppointments.js
│           └── availableAppointments.js-meta.xml
├── sfdx-project.json
└── README.md
```

---

## Installation

### Option A: Install via Terminal (Salesforce CLI)

**1. Clone the repository**

```bash
git clone https://github.com/kalonzoSF/available-appointments-lwc.git
cd available-appointments-lwc
```

**2. Authenticate to your Salesforce org**

If you haven't already authorized your org, log in:

```bash
sf org login web --alias my-org --set-default
```

This opens a browser window. Log in with your Salesforce credentials and authorize the CLI.

To verify your connection:

```bash
sf org display --target-org my-org
```

**3. Deploy the component**

```bash
sf project deploy start --source-dir force-app --target-org my-org
```

**4. Verify the deployment**

```bash
sf project deploy report --target-org my-org
```

You should see both `AvailableAppointmentsController` (Apex class) and `availableAppointments` (LWC) listed as successfully deployed.

**5. (Optional) Deploy with test execution**

For production orgs, include test validation:

```bash
sf project deploy start --source-dir force-app --target-org my-org --test-level RunLocalTests
```

---

### Option B: Install via Claude Code

If you use [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview), you can install directly from the CLI by pasting these instructions.

**1. Clone and deploy**

Tell Claude:

```
Clone the available-appointments-lwc repo from GitHub (kalonzoSF/available-appointments-lwc)
and deploy it to my org [your-org-alias].
```

Claude will run:

```bash
git clone https://github.com/kalonzoSF/available-appointments-lwc.git /tmp/available-appointments-lwc
cd /tmp/available-appointments-lwc
sf project deploy start --source-dir force-app --target-org <your-org-alias>
```

**2. Verify deployment**

Ask Claude:

```
Verify the deployment of available-appointments-lwc to [your-org-alias].
```

Claude will confirm the Apex class and LWC deployed successfully by checking the deployment status.

**3. One-liner prompt**

You can also combine everything into a single prompt:

```
Clone https://github.com/kalonzoSF/available-appointments-lwc.git to a temp directory,
deploy the force-app source to my org [your-org-alias], and verify deployment succeeded.
```

---

## Post-Installation Setup

After deploying, add the component to a page:

### Lightning Record Page / App Page / Home Page

1. Open the target page in **Lightning App Builder**
2. Search for **availableAppointments** in the Components panel
3. Drag it onto the page
4. Save and activate

### Field Service Mobile (Screen Action)

1. Go to **Setup > Object Manager > Work Order > Buttons, Links, and Actions**
2. Create a **New Action**:
   - Action Type: `Lightning Web Component`
   - Lightning Web Component: `c:availableAppointments`
   - Label: `Available Appointments`
3. Add the action to the **Work Order Page Layout** under **Mobile & Lightning Actions**
4. In **Field Service Mobile Settings**, verify the action appears in the Work Order actions list

## Usage

The component automatically detects the current user's Service Resource and loads available appointments in their assigned territories. Technicians can:

1. Allow GPS location access when prompted
2. Set a search radius (5-50 miles)
3. Toggle between list and map views
4. Tap an appointment to view details
5. Self-assign with one tap

## License

MIT
