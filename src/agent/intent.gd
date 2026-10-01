class_name Intent
extends RefCounted
## What the user wants from MIKU, as understood by the local parser (or attached to a direct
## gesture: a click on MIKU or on a world). Pure data (ADR-016).
##
## Kinds:
##   ATTENTION     — the user calls her ("Miku!", "Miku, olha aqui", a click on MIKU)
##   WORLD_TARGET  — the user points at a world ("trabalhe no planeta da esquerda", a click)
##   CONFIG_PATCH  — a change to her configuration (`patch`; structured or a simple phrase)
##   SEMANTIC      — natural/subjective request: only a provider could interpret it
##   UNKNOWN       — nothing recognisable (empty, noise)
## Route: LOCAL (deterministic, no tokens) or PROVIDER (SEMANTIC -> ProviderPort).

enum Kind { ATTENTION, WORLD_TARGET, CONFIG_PATCH, SEMANTIC, UNKNOWN }
enum Route { LOCAL, PROVIDER }

const KIND_NAMES: Array[String] = ["ATTENTION", "WORLD_TARGET", "CONFIG_PATCH", "SEMANTIC", "UNKNOWN"]
const ROUTE_NAMES: Array[String] = ["LOCAL", "PROVIDER"]

var kind: Kind = Kind.UNKNOWN
var route: Route = Route.LOCAL
## Entity the intent concerns: the targeted world id (WORLD_TARGET), &"miku" (ATTENTION), or &"".
var target: StringName = &""
## Original text ("" for a gesture).
var text := ""
## Language detected from the text: "pt" | "en" ("" for gestures / undecided).
var lang := ""
## The requested configuration change (CONFIG_PATCH only).
var patch: StructuredPatch
## Origin of the intent: &"text" | &"click" | &"script".
var source: StringName = &"text"
## Why the parser chose this kind (debug/log: the rule that matched).
var rule := ""


static func make(p_kind: Kind, p_text: String = "", p_target: StringName = &"") -> Intent:
	var i := Intent.new()
	i.kind = p_kind
	i.text = p_text
	i.target = p_target
	i.route = Route.PROVIDER if p_kind == Kind.SEMANTIC else Route.LOCAL
	return i


func kind_name() -> String:
	return KIND_NAMES[kind]


func route_name() -> String:
	return ROUTE_NAMES[route]


func to_dict() -> Dictionary:
	return {"kind": kind_name(), "route": route_name(), "target": target, "text": text, "lang": lang,
		"patch": patch.to_dict() if patch else {}, "source": source, "rule": rule}


func _to_string() -> String:
	return "Intent(%s/%s target=%s patch=%s rule=%s)" % [kind_name(), route_name(), target,
		str(patch) if patch else "-", rule]
