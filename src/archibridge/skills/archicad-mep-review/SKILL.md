---
name: archicad-mep-review
description: Read-only MEP review of an Archicad model. Inventory by domain and type, open ports, elements outside a distribution system, and clashes with the structure. Needs Archicad 28 or newer and the Tapir add-on. Changes nothing.
---

# Archicad MEP review

Use this for "review my MEP model", "find open ducts", "check my pipes" and similar requests. Read the `archibridge` skill first. Every command here runs through `archicad_read`. Change nothing unless the user asks after seeing the report.

These commands need Archicad 28 or newer, and electrical commands need Archicad 30. Confirm the exact parameters with `archicad_command_schema`.

Work through the checks in order, and report what each one found. If a check returns nothing, say so: an empty result can mean the project has no MEP elements.

## 1. Inventory

Call `GetMEPElements` with no filter. Count the results by `domain` (Ventilation, Piping, CableCarrier) and by `type`. An empty `domain` is normal for Equipment.

## 2. Open ports

Call `GetMEPPorts` with the elements from step 1, in batches of a few hundred.

- A port is open when `isPhysicallyConnected` is false.
- Group open ports by domain and by the element's type.
- Report `position` in meters, and `width` and `height` in millimeters.

A port on a terminal or on equipment can be open on purpose, for example a connection to a future phase. Present open ports as items to check, not as errors.

## 3. Elements outside any system

Call `GetMEPDistributionSystems`. Collect every id in each system's `elements`. Any element from step 1 that appears in no system is outside a distribution system.

## 4. Sizes and routes

Call `GetMEPRoutingElements` with the routing elements from step 1. Report the cross sections per domain, and flag a route where the size changes with no transition between two segments.

## 5. Clashes with the structure

Only when the user asks, because this can take time on a large model.

1. Get the structure with `GetElementsByType`, for types such as `Wall`, `Slab`, `Beam` and `Column`.
2. Call `GetCollisions` with the MEP elements as `elementsGroup1` and the structure as `elementsGroup2`.
3. Report the number of clashes per pair of types. Walls and slabs clash wherever a duct or pipe passes through, so expect many results where no opening has been modelled.

## Report

- Start with one line: counts per domain, and the number of open ports.
- Then a short table per check.
- Finish with the three most useful things to fix first.
- To show a problem, pass its ids to `ChangeSelectionOfElements`, then `FitInWindow`, and offer a picture with `archicad_view_image`.
