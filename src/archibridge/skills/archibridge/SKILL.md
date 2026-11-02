---
name: archibridge
description: ArchiBridge working method for Archicad. How to find commands, use metric units, build in visible stages, check with images, and report briefly in the user's language. Read before any build or edit task.
---

# ArchiBridge working method

ArchiBridge users are architects, engineers and BIM coordinators who work in Archicad through you.

## Start

1. Call `archicad_instances`.
   - `status: no_project`: ask the user to open a project.
   - `tapir: null`: only `API.*` commands work. Tell the user to add the Tapir add-on (see INSTALL.md).
   - Several ready instances: ask which project to work in, then pass its `port` on every call.
2. Find commands with `archicad_search_commands`.
3. Read `archicad_command_schema` before the first call of any command. Names and parameters are not guessable. If a result shows `minimumArchicad` above the running version, that command will not work: pick another.

## Talk to the user

- Reply in the user's language. Keep Archicad names (layers, favorites, properties) exactly as they appear in the project.
- Before a build, restate the plan in a few short lines: what you will create, the main sizes, the stages. Ask a question only when something is missing or contradicts itself.
- After each stage, say in one or two lines what changed and how many elements.

## Units

- The API works in meters, square meters, cubic meters, and radians for angles. Users usually speak in meters, centimeters or millimeters, and MEP sizes in millimeters. Convert before sending.
- Report in metric: meters with two decimals for building dimensions, millimeters for MEP sizes.

## Look before you build

- `GetStories`: story indexes and levels. Pass `floorIndex` where a command accepts it.
- `GetFavoritesByType`: use the office's favorites before raw settings. With `favoriteName`, a new element only needs its geometry.
- `GetLayers`, `GetBuildingMaterials`, `GetComposites`, `GetSelectedElements`: use names and ids that exist. Never invent them.

## Build in visible stages

1. One `archicad_modify` call per stage, with every item of the stage in one call.
2. Results have one entry per item, and an item can fail alone. Read them. A successful call does not mean every item worked.
3. Keep the guids that come back. If you redo a stage, delete only those guids.
4. After each stage, check your work: go to the right window with `ChangeWindow` (`{"windowType": "3DModel"}` for 3D, `{"windowType": "FloorPlan", "storyIndex": 0}` for a plan), frame it with `FitInWindow`, then call `archicad_view_image` and look at the picture before the next stage.
5. Usual order: stories, walls, slabs, columns and beams, doors and windows, roofs, zones, then documentation.
6. There is no undo command. The user can press Ctrl+Z in Archicad, and one press undid a whole `CreateWalls` call in testing, so tell the user what one stage would take back. To remove a stage yourself, delete its guids.

## Reading data

- `GetElementsByType` or `GetAllElements` gives ids. `GetDetailsOfElements` gives geometry: pass `fields` to keep it fast.
- For values, find the property with `GetAllProperties`, then call `GetPropertyValuesOfElements`.
- `GetQuantitiesOfElements` gives Archicad's calculated quantities.
- Results above 60,000 characters are saved to a file. Use `savedTo`, or ask for less.

## Safety

- Never delete, move or change elements the user did not ask about.
- Before a large change on a real project, suggest working on a copy.
- `SaveProject` writes over the user's file. Run it only when asked.
- In a Teamwork project, elements must be reserved before they can change. Use `GetReservationStatusOfElements` and `ReserveElements`, and never release what the user reserved.
- `OpenProject`, `CloseProject`, `NewProject`, `QuitArchicad`, `TeamworkSend` and `TeamworkReceive` are restricted. Ask the user to do those in Archicad.
- `GetPointFromUser` and `GetElementFromUser` stop Archicad until the user clicks. Tell the user first.

## Show results

- Show what you made or found with `ChangeSelectionOfElements` or `HighlightElements`, then `FitInWindow`.
- Summarize in numbers: counts, lengths and areas in metric.
