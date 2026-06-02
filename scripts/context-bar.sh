#!/usr/bin/env bash

C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'
C_BAR_EMPTY='\033[38;5;238m'
C_ACCENT='\033[38;5;74m'

input=$(cat)

# ── extract fields (single jq call, newline-separated) ───────────
{
    IFS= read -r model
    IFS= read -r cwd
    IFS= read -r session_name
    IFS= read -r session_id
    IFS= read -r transcript_path
    IFS= read -r used_pct
    IFS= read -r max_ctx
    IFS= read -r total_in
    IFS= read -r cost_usd
} < <(jq -r '
    .model.display_name // .model.id // "?",
    .workspace.current_dir // .cwd // "",
    .session_name // "",
    .session_id // "",
    .transcript_path // "",
    (.context_window.used_percentage // 0 | tostring),
    (.context_window.context_window_size // 200000 | tostring),
    (.context_window.total_input_tokens // 0 | tostring),
    (.cost.total_cost_usd // "" | tostring)
' <<<"$input")

dir=$(basename "$cwd" 2>/dev/null || echo "?")

max_k=$((max_ctx / 1000))
if [[ $max_k -ge 1000 ]]; then max_display="$((max_k / 1000))M"; else max_display="${max_k}k"; fi
ctx_k=$(awk "BEGIN { k=$total_in/1000; if(k<10) printf \"%.1fk\",k; else printf \"%.0fk\",k }")

cost_display=""
if [[ -n "$cost_usd" ]]; then
    cost_display=$(awk -v c="$cost_usd" 'BEGIN {
        if      (c < 0.005) printf "<$0.01"
        else if (c < 10)    printf "$%.2f", c
        else                printf "$%.1f", c
    }')
fi

# ── git info ─────────────────────────────────────────────────────
branch=""; file_count=0; single_file=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        porcelain=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null)
        file_count=$(printf '%s\n' "$porcelain" | grep -c .)
        [[ "$file_count" -eq 1 ]] && single_file=$(printf '%s\n' "$porcelain" | head -1 | sed 's/^...//')
    fi
fi

git_detail=""
if [[ -n "$branch" ]]; then
    if   [[ "$file_count" -eq 0 ]]; then git_detail="(clean)"
    elif [[ "$file_count" -eq 1 ]]; then git_detail="(${single_file})"
    else                                  git_detail="(${file_count} files)"
    fi
fi

# ── progress bar (10 cells, three-tier) ──────────────────────────
pct=$used_pct
[[ $pct -gt 100 ]] && pct=100
bar_inner=""
for ((i=0; i<10; i++)); do
    cell_pct=$((pct - i * 10))
    if   [[ $cell_pct -ge 8 ]]; then bar_inner+="█"
    elif [[ $cell_pct -ge 3 ]]; then bar_inner+="▄"
    else                              bar_inner+="\033[38;5;238m░\033[38;5;74m"
    fi
done
bar="${C_ACCENT}${bar_inner}${C_RESET}"

# ── responsive layout (greedy fit) ───────────────────────────────
COLS=${COLUMNS:-80}
SN=3  # " | " separator width

pct_label="${pct}% (${ctx_k}/${max_display})"

# Display order, with priority (lower = keep longer).
# Drop order on narrow terminals: session → git_detail → branch → cost → dir.
names=(    model                              bar                                            cost                                     dir                          branch                       git_detail                  session )
texts=(    "${C_ACCENT}${model}${C_RESET}"    "${bar} ${C_GRAY}${pct_label}${C_RESET}"       "${C_GRAY}💰 ${cost_display}${C_RESET}"  "${C_GRAY}🗂️ ${dir}${C_RESET}"  "${C_GRAY}🌿 ${branch}${C_RESET}"  "${C_GRAY}${git_detail}${C_RESET}" "${C_GRAY}◈ ${session_name}${C_RESET}" )
widths=(   ${#model}                          $((10 + 1 + ${#pct_label}))                    $((3 + ${#cost_display}))                $((3 + ${#dir}))             $((3 + ${#branch}))          ${#git_detail}              $((2 + ${#session_name})) )
prios=(    0                                  1                                              3                                        2                            4                            5                           6 )
# Empty-segment guards (zero out width so they're skipped).
[[ -z "$cost_display" ]] && widths[2]=0
[[ -z "$branch"       ]] && { widths[4]=0; widths[5]=0; }
[[ -z "$git_detail"   ]] && widths[5]=0
[[ -z "$session_name" ]] && widths[6]=0

# Build "kept" mask: start with all non-empty, drop highest-priority-number while too wide.
kept=()
for i in "${!names[@]}"; do [[ ${widths[$i]} -gt 0 ]] && kept+=("$i"); done

total_width() {
    local sum=0 first=1
    for i in "$@"; do
        if [[ $first -eq 1 ]]; then sum=${widths[$i]}; first=0
        else sum=$(( sum + SN + widths[$i] )); fi
    done
    echo "$sum"
}

while [[ ${#kept[@]} -gt 2 && $(total_width "${kept[@]}") -gt $COLS ]]; do
    drop_idx=-1; drop_prio=-1
    for k in "${!kept[@]}"; do
        seg=${kept[$k]}
        if [[ ${prios[$seg]} -gt $drop_prio ]]; then
            drop_prio=${prios[$seg]}; drop_idx=$k
        fi
    done
    [[ $drop_idx -lt 0 ]] && break
    unset 'kept[drop_idx]'; kept=("${kept[@]}")
done

line1=""
first=1
for i in "${kept[@]}"; do
    if [[ $first -eq 1 ]]; then line1="${texts[$i]}"; first=0
    else line1+="${C_GRAY} | ${C_RESET}${texts[$i]}"; fi
done
printf '%b\n' "$line1"

# ── line 2: last user message, truncated to terminal width ────────
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    last_msg=$(tail -n 500 "$transcript_path" | jq -rs '
        def skip: startswith("[Request interrupted") or startswith("[Request cancelled") or . == "";
        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or
                (type == "array" and any(.[]; .type == "text")))] |
        reverse |
        map(.message.content |
            if type == "string" then .
            else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("\n"; " ") | gsub("  +"; " ")) |
        map(select(skip | not)) |
        first // ""
    ' 2>/dev/null)

    if [[ -n "$last_msg" ]]; then
        max_msg=$((COLS - 6))
        [[ $max_msg -lt 10 ]] && max_msg=10
        if [[ ${#last_msg} -gt $max_msg ]]; then
            printf '%b\n' "${C_GRAY}💬 ${last_msg:0:${max_msg}}...${C_RESET}"
        else
            printf '%b\n' "${C_GRAY}💬 ${last_msg}${C_RESET}"
        fi
    fi
fi
