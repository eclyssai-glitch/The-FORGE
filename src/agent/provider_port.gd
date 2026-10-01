class_name ProviderPort
extends RefCounted
## PORT (interface) for a future provider that would interpret SEMANTIC requests (ADR-016).
##
## There is NO implementation and NO registry here. This project keeps the KORIUM isolation rule:
## the future binding is meant to be the KORIUM provider registry, which this project does not
## access, import or connect to (CLAUDE.md, "Isolamento"). No network, no tokens, no keys.
## This base class is the only port that exists in the game and it is always unavailable:
## `is_available() == false`, `request()` answers {"ok": false, "reason": "provider_unavailable"}.
## The InteractionRouter then makes MIKU decline gracefully and applies nothing.
##
## Contract a provider must honour (the same validation path as the local parser):
##   request(intent, context) -> {
##       "ok": true,
##       "actions": [ {"action": <ActionVocabulary name>, "args": {...}}, ... ],   # only the vocabulary
##       "mutation": {"file": "miku.config.json", "path": "<section.key>", "value": <number>}  # optional
##   }
## `validate_response()` checks it: unknown actions or arguments reject the whole response; the
## mutation becomes a StructuredPatch (source &"provider") that still goes through
## ConfigValidator before MikuConfig applies it. A provider never touches bones, transforms,
## AnimationTree, camera or files: MIKU's runtime decides how the actions are performed.
## `context` given by the router: {"config": MikuConfig.values(), "worlds": [...], "vocabulary": ActionVocabulary.ALL}.

const UNAVAILABLE := "provider_unavailable"


## Always false in this project (no provider is bound; see the class doc).
func is_available() -> bool:
	return false


## Short description for logs and the AGENT doc.
func describe() -> String:
	return "unbound provider port (future binding: KORIUM provider registry — not accessed)"


## The provider's answer for a SEMANTIC intent. The unbound port refuses.
func request(_intent: Intent, _context: Dictionary) -> Dictionary:
	return {"ok": false, "reason": UNAVAILABLE}


## Validates a provider response. Returns {"ok": bool, "actions": Array (normalized steps),
## "patch": StructuredPatch or null, "errors": PackedStringArray, "reason": String}.
## Any invalid action, argument or malformed mutation makes the whole response invalid.
static func validate_response(response: Variant) -> Dictionary:
	var out := {"ok": false, "actions": [], "patch": null, "errors": PackedStringArray(), "reason": ""}
	if not response is Dictionary:
		out["reason"] = "response is not a dictionary"
		return out
	var r := response as Dictionary
	if not bool(r.get("ok", false)):
		out["reason"] = String(r.get("reason", UNAVAILABLE))
		return out
	var errors := PackedStringArray()
	for key: Variant in r:
		if not String(key) in ["ok", "actions", "mutation", "reason"]:
			errors.append("unknown response field %s" % key)
	var actions: Variant = r.get("actions", [])
	errors.append_array(ActionVocabulary.validate_plan(actions))
	var steps: Array = []
	if errors.is_empty():
		for s: Dictionary in actions:
			steps.append(ActionVocabulary.step(s["action"], s.get("args", {})))
	var patch: StructuredPatch = null
	if r.has("mutation") and r["mutation"] != null:
		patch = StructuredPatch.from_mutation(r["mutation"])
		if patch == null:
			errors.append("malformed mutation (expected {file, path, value})")
	if not errors.is_empty():
		out["errors"] = errors
		out["reason"] = "invalid provider response"
		return out
	out["ok"] = true
	out["actions"] = steps
	out["patch"] = patch
	return out
