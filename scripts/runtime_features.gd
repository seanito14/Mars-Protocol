class_name RuntimeFeaturesSingleton
extends Node

const SUDO_AI_ENABLED: bool = false

func is_sudo_ai_enabled() -> bool:
	return SUDO_AI_ENABLED

func is_voice_bridge_enabled() -> bool:
	return SUDO_AI_ENABLED
