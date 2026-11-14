#!/usr/bin/env bash
set -euo pipefail

# SEO Skills Installer (Google Antigravity & Claude Code)
# Wraps everything in main() to prevent partial execution on network failure

show_help() {
    cat << 'EOF'
Usage: install.sh [OPTIONS]

Installs SEO skills and tools for Google Antigravity and/or Claude Code.

Options:
  -a, --antigravity, --agy   Install skills for Google Antigravity (default)
  -c, --claude               Install skills for Claude Code
  -b, --all, --both          Install skills for both Antigravity and Claude Code
  -t, --target <name>        Explicit target ('antigravity', 'claude', or 'all')
  -w, --workspace            Install into project workspace (.agents/skills) instead of global user dir
  -g, --global               Install into user home directory (~/.agents/skills) (default)
  -h, --help                 Show this help message

Environment Variables:
  CLAUDE_SEO_TARGET          Override target ('antigravity', 'claude', 'all')
  CLAUDE_SEO_TAG             Pin release tag (default: v2.6.0)
  CLAUDE_SEO_PYTHON          Path to specific Python interpreter (3.11 - 3.14)
EOF
}

install_for_target() {
    local target_type="$1"
    local skills_base="$2"
    local agent_dir="$3"
    local source_dir="$4"

    local SKILL_DIR="${skills_base}/seo"
    local AGENT_DIR="${agent_dir}"

    echo "════════════════════════════════════════"
    if [ "${target_type}" = "antigravity" ]; then
        echo "║   Target: Google Antigravity         ║"
    else
        echo "║   Target: Claude Code                ║"
    fi
    echo "║   Skills: ${skills_base}"
    echo "════════════════════════════════════════"
    echo ""

    # Create directories
    mkdir -p "${SKILL_DIR}"
    mkdir -p "${AGENT_DIR}"

    # Copy skill files
    echo "→ Installing skill files..."
    cp -r "${source_dir}/skills/seo/"* "${SKILL_DIR}/"

    # Copy sub-skills
    if [ -d "${source_dir}/skills" ]; then
        for skill_dir in "${source_dir}/skills"/*/; do
            [ -d "${skill_dir}" ] || continue
            skill_name=$(basename "${skill_dir}")
            target="${skills_base}/${skill_name}"
            mkdir -p "${target}"
            cp -r "${skill_dir}"* "${target}/"
        done
    fi

    # Copy schema templates
    if [ -d "${source_dir}/schema" ]; then
        mkdir -p "${SKILL_DIR}/schema"
        cp -r "${source_dir}/schema/"* "${SKILL_DIR}/schema/"
    fi

    # Copy deterministic data files consumed by bundled scripts such as
    # seo_updates.py. Keep the repository-relative data/ layout intact.
    if [ -d "${TEMP_DIR}/claude-seo/data" ]; then
        mkdir -p "${SKILL_DIR}/data"
        cp -r "${TEMP_DIR}/claude-seo/data/"* "${SKILL_DIR}/data/"
    elif [ -d "${source_dir}/data" ]; then
        mkdir -p "${SKILL_DIR}/data"
        cp -r "${source_dir}/data/"* "${SKILL_DIR}/data/"
    fi

    # Copy reference docs
    if [ -d "${source_dir}/pdf" ]; then
        mkdir -p "${SKILL_DIR}/pdf"
        cp -r "${source_dir}/pdf/"* "${SKILL_DIR}/pdf/"
    fi

    # Copy agents
    echo "→ Installing subagents..."
    mkdir -p "${SKILL_DIR}/agents"
    if [ -d "${source_dir}/agents" ]; then
        cp -r "${source_dir}/agents/"*.md "${AGENT_DIR}/" 2>/dev/null || true
        cp -r "${source_dir}/agents/"*.md "${SKILL_DIR}/agents/" 2>/dev/null || true
    fi

    # For Antigravity, also copy AGENTS.md to skill dir
    if [ -f "${source_dir}/AGENTS.md" ]; then
        cp "${source_dir}/AGENTS.md" "${SKILL_DIR}/AGENTS.md" 2>/dev/null || true
    fi

    # Copy shared scripts
    if [ -d "${source_dir}/scripts" ]; then
        mkdir -p "${SKILL_DIR}/scripts"
        cp -r "${source_dir}/scripts/"* "${SKILL_DIR}/scripts/"
    fi

    # Copy the stable runtime launcher. It ships in scripts/ (never a top-level
    # bin/, which hosted marketplaces reject) and resolves runtime.py as a
    # sibling, so the manual layout below already matches the repository layout.
    if [ -f "${TEMP_DIR}/claude-seo/scripts/claude-seo" ]; then
        mkdir -p "${SKILL_DIR}/scripts"
        cp "${TEMP_DIR}/claude-seo/scripts/claude-seo" "${SKILL_DIR}/scripts/claude-seo"
        chmod +x "${SKILL_DIR}/scripts/claude-seo"
    elif [ -f "${source_dir}/scripts/claude-seo" ]; then
        mkdir -p "${SKILL_DIR}/scripts"
        cp "${source_dir}/scripts/claude-seo" "${SKILL_DIR}/scripts/claude-seo"
        chmod +x "${SKILL_DIR}/scripts/claude-seo"
    fi

    # Copy hooks
    if [ -d "${source_dir}/hooks" ]; then
        mkdir -p "${SKILL_DIR}/hooks"
        cp -r "${source_dir}/hooks/"* "${SKILL_DIR}/hooks/"
        chmod +x "${SKILL_DIR}/hooks/"*.sh 2>/dev/null || true
        chmod +x "${SKILL_DIR}/hooks/"*.py 2>/dev/null || true
        echo "  Note: hook enforcement requires plugin install; manual hook copy is best-effort."
    fi

    # Copy extensions (optional add-ons: dataforseo, banana)
    if [ -d "${source_dir}/extensions" ]; then
        echo "=> Installing extensions..."
        for ext_dir in "${source_dir}/extensions"/*/; do
            [ -d "${ext_dir}" ] || continue
            ext_name=$(basename "${ext_dir}")
            # Extension skills
            if [ -d "${ext_dir}skills" ]; then
                for ext_skill in "${ext_dir}skills"/*/; do
                    [ -d "${ext_skill}" ] || continue
                    ext_skill_name=$(basename "${ext_skill}")
                    target="${skills_base}/${ext_skill_name}"
                    mkdir -p "${target}"
                    cp -r "${ext_skill}"* "${target}/"
                done
            fi
            # Extension agents
            if [ -d "${ext_dir}agents" ]; then
                cp -r "${ext_dir}agents/"*.md "${AGENT_DIR}/" 2>/dev/null || true
                cp -r "${ext_dir}agents/"*.md "${SKILL_DIR}/agents/" 2>/dev/null || true
            fi
            # Extension references
            if [ -d "${ext_dir}references" ]; then
                mkdir -p "${SKILL_DIR}/extensions/${ext_name}/references"
                cp -r "${ext_dir}references/"* "${SKILL_DIR}/extensions/${ext_name}/references/"
            fi
            # Extension scripts
            if [ -d "${ext_dir}scripts" ]; then
                mkdir -p "${SKILL_DIR}/extensions/${ext_name}/scripts"
                cp -r "${ext_dir}scripts/"* "${SKILL_DIR}/extensions/${ext_name}/scripts/"
            fi
        done
    fi

    # Copy requirements.txt to skill dir so users can retry later
    cp "${source_dir}/requirements.txt" "${SKILL_DIR}/requirements.txt" 2>/dev/null || true
    if [ -f "${source_dir}/.claude-plugin/plugin.json" ]; then
        cp "${source_dir}/.claude-plugin/plugin.json" "${SKILL_DIR}/runtime-plugin.json" 2>/dev/null || true
        cp "${source_dir}/.claude-plugin/plugin.json" "${SKILL_DIR}/plugin.json" 2>/dev/null || true
    fi

    # Manual installs have no ${CLAUDE_PLUGIN_ROOT}, so rewrite the canonical
    # launcher token to the absolute installed path. Rewrite only exact files
    # copied from this checkout during this install. The substitution is
    # idempotent: it consumes the plugin-root token, so a second pass matches
    # nothing. In a POSIX basic regular expression "$" is literal unless it ends
    # the expression, so ${CLAUDE_PLUGIN_ROOT} needs no escaping here.
    # Reference paths are opened with the Read tool, which does not expand
    # variables, so ${CLAUDE_PLUGIN_ROOT}/skills/ becomes the absolute path.
    local skills_root_esc
    skills_root_esc=$(printf '%s' "${skills_base}/" | sed 's/[#&\\]/\\&/g')
    local launcher_path="${SKILL_DIR}/scripts/claude-seo"
    local launcher_esc
    launcher_esc=$(printf '%s' "${launcher_path}" | sed 's/[#&\\]/\\&/g')

    rewrite_doc() {
        local doc="$1" temp_doc
        temp_doc="${doc}.claude-seo-tmp"
        if [ "${target_type}" = "antigravity" ]; then
            sed -e "s#\${CLAUDE_PLUGIN_ROOT}/skills/#${skills_root_esc}#g" \
                -e "s#\"\${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo\" run#\"${launcher_esc}\" run#g" \
                -e "s#\"\${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo\" setup#\"${launcher_esc}\" setup#g" \
                -e "s#\"\${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo\" doctor#\"${launcher_esc}\" doctor#g" \
                -e "s#\"\${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo\"#\"${launcher_esc}\"#g" \
                -e "s#\"\$HOME/\.claude/skills/seo/scripts/claude-seo\"#\"${launcher_esc}\"#g" \
                -e "s#\$HOME/\.claude/skills/#${skills_root_esc}#g" \
                "${doc}" > "${temp_doc}"
        else
            sed -e "s#\${CLAUDE_PLUGIN_ROOT}/skills/#${skills_root_esc}#g" \
                -e 's#"${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo" run#"$HOME/.claude/skills/seo/scripts/claude-seo" run#g' \
                -e 's#"${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo" setup#"$HOME/.claude/skills/seo/scripts/claude-seo" setup#g' \
                -e 's#"${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo" doctor#"$HOME/.claude/skills/seo/scripts/claude-seo" doctor#g' \
                "${doc}" > "${temp_doc}"
        fi
        mv "${temp_doc}" "${doc}"
    }

    for source_root in "${source_dir}/skills"/*; do
        [ -d "${source_root}" ] || continue
        skill_name=$(basename "${source_root}")
        while IFS= read -r -d '' source_doc; do
            relative_doc=${source_doc#"${source_root}/"}
            doc="${skills_base}/${skill_name}/${relative_doc}"
            [ -f "${doc}" ] && rewrite_doc "${doc}"
        done < <(find "${source_root}" -type f -name '*.md' -print0)
    done

    if [ -d "${source_dir}/extensions" ]; then
        for source_root in "${source_dir}/extensions"/*/skills/*; do
            [ -d "${source_root}" ] || continue
            skill_name=$(basename "${source_root}")
            while IFS= read -r -d '' source_doc; do
                relative_doc=${source_doc#"${source_root}/"}
                doc="${skills_base}/${skill_name}/${relative_doc}"
                [ -f "${doc}" ] && rewrite_doc "${doc}"
            done < <(find "${source_root}" -type f -name '*.md' -print0)
        done

        for source_root in "${source_dir}/extensions"/*/references; do
            [ -d "${source_root}" ] || continue
            ext_name=$(basename "$(dirname "${source_root}")")
            while IFS= read -r -d '' source_doc; do
                relative_doc=${source_doc#"${source_root}/"}
                doc="${SKILL_DIR}/extensions/${ext_name}/references/${relative_doc}"
                [ -f "${doc}" ] && rewrite_doc "${doc}"
            done < <(find "${source_root}" -type f -name '*.md' -print0)
        done
    fi

    for source_doc in "${source_dir}/agents"/*.md "${source_dir}/extensions"/*/agents/*.md; do
        [ -f "${source_doc}" ] || continue
        doc="${AGENT_DIR}/$(basename "${source_doc}")"
        [ -f "${doc}" ] && rewrite_doc "${doc}"
        doc_in_skill="${SKILL_DIR}/agents/$(basename "${source_doc}")"
        [ -f "${doc_in_skill}" ] && rewrite_doc "${doc_in_skill}"
    done

    # Setup isolated Python runtime
    echo "→ Creating isolated Python runtime..."
    set +e
    "${SKILL_DIR}/scripts/claude-seo" setup
    runtime_status=$?
    set -e
    if [ "${runtime_status}" -ne 0 ] && [ "${runtime_status}" -ne 10 ]; then
        echo "✗ Core Python runtime setup failed. Installation is incomplete." >&2
        return 1
    elif [ "${runtime_status}" -eq 10 ]; then
        echo "⚠ Core runtime installed, but Chromium setup is incomplete." >&2
    fi

    # For Antigravity: register ~/.agents/skills in ~/.gemini/config/skills.json if config dir exists
    if [ "${target_type}" = "antigravity" ] && [ -d "${HOME}/.gemini/config" ]; then
        if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
            py_cmd="python3"
            command -v python3 >/dev/null 2>&1 || py_cmd="python"
            "$py_cmd" -c '
import json, os
p = os.path.expanduser("~/.gemini/config/skills.json")
data = {"entries": []}
if os.path.exists(p):
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        pass
entries = data.setdefault("entries", [])
paths = [e.get("path") for e in entries if isinstance(e, dict)]
target_path = "~/.agents/skills"
if target_path not in paths:
    entries.append({"path": target_path})
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass
' 2>/dev/null || true
        fi
    fi

    echo ""
    echo "✓ Installed successfully for ${target_type}!"
    echo "  Location: ${skills_base}"
    echo ""
}

main() {
    REPO_URL="${CLAUDE_SEO_REPO:-https://github.com/AgriciDaniel/claude-seo}"
    # Pin to a specific release tag to prevent silent updates from main.
    # This default MUST be bumped on every release. CI guard
    # (tests/test_manifest_consistency.py) enforces this matches plugin.json.
    # Override: CLAUDE_SEO_TAG=main bash install.sh
    REPO_TAG="${CLAUDE_SEO_TAG:-v2.6.0}"
    TARGET="${CLAUDE_SEO_TARGET:-${TARGET:-antigravity}}"
    SCOPE="global"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--antigravity|--agy)
                TARGET="antigravity"
                shift
                ;;
            -c|--claude)
                TARGET="claude"
                shift
                ;;
            -b|--all|--both)
                TARGET="all"
                shift
                ;;
            -w|--workspace)
                SCOPE="workspace"
                shift
                ;;
            -g|--global)
                SCOPE="global"
                shift
                ;;
            -t|--target)
                TARGET="$2"
                shift 2
                ;;
            --target=*)
                TARGET="${1#*=}"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Run '$0 --help' for usage." >&2
                exit 1
                ;;
        esac
    done

    echo "════════════════════════════════════════"
    echo "║   Claude SEO - Installer             ║"
    echo "║   Target: ${TARGET}                   ║"
    echo "════════════════════════════════════════"
    echo ""

    # Check prerequisites. The runtime launcher performs cross-platform Python
    # resolution and validates the minimum supported version.
    command -v git >/dev/null 2>&1 || { echo "✗ Git is required but not installed."; exit 1; }

    # Resolve source directory (use local repo if running from checkout, else clone)
    local script_dir
    script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

    TEMP_DIR=$(mktemp -d)
    cleanup() { rm -rf -- "${TEMP_DIR}"; }
    trap cleanup EXIT

    local source_dir=""
    if [ -d "${script_dir}/skills/seo" ]; then
        source_dir="${script_dir}"
        # Populate TEMP_DIR/claude-seo with symlinks/copies so layout paths match
        mkdir -p "${TEMP_DIR}/claude-seo"
        cp -r "${script_dir}/data" "${TEMP_DIR}/claude-seo/" 2>/dev/null || true
        cp -r "${script_dir}/scripts" "${TEMP_DIR}/claude-seo/" 2>/dev/null || true
    else
        echo "↓ Downloading Claude SEO (${REPO_TAG})..."
        if ! git clone --depth 1 --branch "${REPO_TAG}" "${REPO_URL}" "${TEMP_DIR}/claude-seo" 2>/dev/null; then
            echo "✗ Failed to clone ${REPO_URL} (${REPO_TAG})" >&2
            exit 1
        fi
        source_dir="${TEMP_DIR}/claude-seo"
    fi

    # Determine targets to install
    if [ "${TARGET}" = "antigravity" ] || [ "${TARGET}" = "all" ] || [ "${TARGET}" = "both" ]; then
        local agy_skills_base
        local agy_agent_dir
        if [ "${SCOPE}" = "workspace" ]; then
            agy_skills_base="$(pwd)/.agents/skills"
            agy_agent_dir="$(pwd)/.agents/agents"
        else
            agy_skills_base="${HOME}/.agents/skills"
            agy_agent_dir="${HOME}/.agents/agents"
        fi
        install_for_target "antigravity" "${agy_skills_base}" "${agy_agent_dir}" "${source_dir}"
    fi

    if [ "${TARGET}" = "claude" ] || [ "${TARGET}" = "all" ] || [ "${TARGET}" = "both" ]; then
        local claude_skills_base
        local claude_agent_dir
        if [ "${SCOPE}" = "workspace" ]; then
            claude_skills_base="$(pwd)/.claude/skills"
            claude_agent_dir="$(pwd)/.claude/agents"
        else
            claude_skills_base="${HOME}/.claude/skills"
            claude_agent_dir="${HOME}/.claude/agents"
        fi
        install_for_target "claude" "${claude_skills_base}" "${claude_agent_dir}" "${source_dir}"
    fi

    echo "════════════════════════════════════════"
    echo "✓ Installation complete!"
    echo "════════════════════════════════════════"
    echo ""
    if [ "${TARGET}" = "antigravity" ] || [ "${TARGET}" = "all" ] || [ "${TARGET}" = "both" ]; then
        echo "Google Antigravity Usage:"
        echo "  1. Start Antigravity: agy (or open Antigravity IDE / Desktop)"
        echo "  2. Skills are automatically discovered in ~/.agents/skills"
        echo "  3. Use slash commands or natural language in chat:"
        echo "     • /seo audit https://example.com"
        echo "     • /seo technical https://example.com"
        echo "     • \"Run an SEO audit on https://example.com\""
        echo ""
    fi
    if [ "${TARGET}" = "claude" ] || [ "${TARGET}" = "all" ] || [ "${TARGET}" = "both" ]; then
        echo "Claude Code Usage:"
        echo "  1. Start Claude Code:  claude"
        echo "  2. Run commands:       /seo audit https://example.com"
        echo ""
    fi
    echo "To uninstall:"
    echo "  curl -fsSL ${REPO_URL}/raw/main/uninstall.sh | bash"
}

main "$@"
