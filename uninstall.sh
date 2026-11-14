#!/usr/bin/env bash
# claude-seo manual-install uninstaller (Unix / macOS / Linux)
#
# Removes the orchestrator skill (~/.claude/skills/seo), all sub-skills
# (~/.claude/skills/seo-*), and all sub-agents (~/.claude/agents/seo-*.md).
#
# Uses glob enumeration rather than a hardcoded list so future skill
# additions are cleaned up automatically without releasing a new
# uninstaller.
#
# Plugin-install users should use Claude Code's own command instead:
#   /plugin uninstall claude-seo@agricidaniel-claude-seo
#   /plugin marketplace remove AgriciDaniel/claude-seo
# SEO uninstaller (Google Antigravity & Claude Code)
set -euo pipefail

remove_from_target() {
    local target_skills="$1"
    local target_agents="$2"
    local count_skills=0
    local count_agents=0

    # Allow empty globs to expand to nothing rather than the literal pattern
    shopt -s nullglob

    # Remove orchestrator if present
    if [ -d "${target_skills}/seo" ]; then
        rm -rf "${target_skills}/seo"
        echo "  Removed: ${target_skills}/seo"
        count_skills=$((count_skills + 1))
    fi

    # Remove every seo-* sub-skill directory
    for skill_path in "${target_skills}"/seo-*; do
        if [ -d "${skill_path}" ]; then
            rm -rf "${skill_path}"
            echo "  Removed: ${skill_path}"
            count_skills=$((count_skills + 1))
        fi
    done

    # Remove every seo-*.md agent file
    for agent_path in "${target_agents}"/seo-*.md; do
        if [ -f "${agent_path}" ]; then
            rm -f "${agent_path}"
            echo "  Removed: ${agent_path}"
            count_agents=$((count_agents + 1))
        fi
    done

    shopt -u nullglob
    echo "$((count_skills + count_agents))"
}

main() {
    echo "→ Uninstalling SEO skills..."

    local removed_skills=0
    local removed_agents=0

    # Allow empty globs to expand to nothing rather than the literal pattern
    shopt -s nullglob

    for s_base in "${HOME}/.agents/skills" "${HOME}/.claude/skills"; do
        if [ -d "${s_base}/seo" ]; then
            rm -rf "${s_base}/seo"
            echo "  Removed: ${s_base}/seo"
            removed_skills=$((removed_skills + 1))
        fi
        for skill_path in "${s_base}"/seo-*; do
            if [ -d "${skill_path}" ]; then
                rm -rf "${skill_path}"
                echo "  Removed: ${skill_path}"
                removed_skills=$((removed_skills + 1))
            fi
        done
    done

    for a_base in "${HOME}/.agents/agents" "${HOME}/.claude/agents"; do
        for agent_path in "${a_base}"/seo-*.md; do
            if [ -f "${agent_path}" ]; then
                rm -f "${agent_path}"
                echo "  Removed: ${agent_path}"
                removed_agents=$((removed_agents + 1))
            fi
        done
    done

    shopt -u nullglob

    if [ "${removed_skills}" -eq 0 ] && [ "${removed_agents}" -eq 0 ]; then
        echo "  Nothing to remove. Claude SEO does not appear to be installed."
        echo "  If you installed via /plugin install, run /plugin uninstall instead."
        return 0
    fi

    echo "✓ Claude SEO uninstalled (${removed_skills} skill dirs, ${removed_agents} agent files)."
}

main "$@"
