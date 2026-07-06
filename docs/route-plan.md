# Route Plan

Route Plan converts product stages and loop budget into an executable trip boundary.

It is still descriptive. Console MCP or the launcher executes the selected stage.

## Fields

- `startStage`: first stage for this trip
- `nextDelegateStage`: stage selected for the next delegate request
- `allowedStages`: stages allowed by the current budget
- `remainingBudget`: numeric budget when bounded
- `stopPolicy`: stop condition for the trip

## Examples

Default single-step mode allows one stage.

Bounded mode allows up to `--max-iterations=N` stages.

RC mode allows the route to continue until RC completion or a block boundary.

## Boundary

Route Plan decides distance. Delegate Contract describes execution. Console MCP executes.
