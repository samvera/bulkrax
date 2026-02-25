---
name: Guided import bug report
about: Report a bug in the Bulkrax guided import (importer stepper) flow
title: "[Guided import]: "
labels: ["bug", "triage", "guided-import"]
assignees: ""
---

## Description

A clear description of the guided import bug (e.g. validation wrong, stepper stuck, upload fails, wrong column mapping).

## Which step?

Which step of the guided import did the bug occur on?

- [ ] **Step 1** – Configure importer / select admin set / upload CSV (and optional zip)
- [ ] **Step 2** – Validation (results, errors, or warnings)
- [ ] **Step 3** – Review / run import
- [ ] Other (describe):

## Steps to reproduce

1. Start a new guided import (e.g. from the importer list).
2. On Step 1: select admin set **…** ; upload **…** (CSV only / CSV + zip).
3. (If relevant) Proceed to Step 2 / Step 3 and describe what you did.
4. Describe where it went wrong (e.g. "Validation said X but …", "Next button disabled", "Error message Y").

## Expected behavior

What you expected to happen at that step.

## Actual behavior

What actually happened (exact messages, UI state, or errors).

## Screenshots

Please add screenshots of the guided import UI at the step where the bug occurs (e.g. Step 1 form, Step 2 validation panel, Step 3 review). You can drag and drop images into this issue.

## Sample files / links to importers

To help reproduce the issue, attach (with sensitive data removed):

- A minimal **CSV** that triggers the bug, and  
- If the bug involves file validation, the **zip** (or list of filenames) you used.
- Link to the importer with the issue


## Additional context

Any other details (e.g. custom field mappings, multi-tenant, specific work type) that might matter.
