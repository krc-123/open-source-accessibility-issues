## Summary by group

| sample | group | issues | repos | closed_share | closed_90d | closed_365d | not_planned_share | km_median_days | median_comments |
|---|---|---|---|---|---|---|---|---|---|
| all collected issues | accessibility | 1,014 |  27 | 0.74 | 0.49 | 0.62 | 0.11 | 100.35 | 2 |
| all collected issues | bug | 30,082 | 235 | 0.84 | 0.64 | 0.77 | 0.14 |  19.00 | 2 |
| repositories with both groups | accessibility |   809 |  19 | 0.74 | 0.51 | 0.63 | 0.12 |  78.80 | 3 |
| repositories with both groups | bug | 3,475 |  19 | 0.75 | 0.55 | 0.68 | 0.09 |  52.60 | 3 |
| repositories with both groups, without microsoft/vscode | accessibility |   309 |  18 | 0.59 | 0.25 | 0.37 | 0.10 | 890.30 | 3 |
| repositories with both groups, without microsoft/vscode | bug | 3,282 |  18 | 0.75 | 0.55 | 0.68 | 0.10 |  54.60 | 3 |
| matched opening windows (strict) | accessibility |   158 |  14 | 0.64 | 0.32 | 0.46 | 0.09 | 485.80 | 3 |
| matched opening windows (strict) | bug | 3,189 |  19 | 0.75 | 0.55 | 0.69 | 0.10 |  49.00 | 3 |

## Cox models (closure hazard, stratified by repository)

| sample | hazard_ratio_a11y_vs_bug | lower95 | upper95 | p | n | events | repos |
|---|---|---|---|---|---|---|---|
| repositories with both groups, year adjusted | 0.608 | 0.536 | 0.690 | 0 | 4,284 | 3,198 | 19 |
| without microsoft/vscode, year adjusted | 0.302 | 0.248 | 0.367 | 0 | 3,591 | 2,644 | 18 |
| matched opening windows (strict) | 0.494 | 0.397 | 0.614 | 0 | 3,347 | 2,498 | 19 |

## By WCAG category

| wcag_category | wcag_criteria | issues | closed_share | closed_90d | not_planned |
|---|---|---|---|---|---|
| screen_reader | 4.1.2 Name, Role, Value; 1.3.1 Info and Relationships | 512 | 0.76 | 0.49 | 0.10 |
| other | NA | 257 | 0.77 | 0.56 | 0.14 |
| keyboard_focus | 2.1.1 Keyboard; 2.4.7 Focus Visible; 2.4.3 Focus Order | 163 | 0.74 | 0.46 | 0.10 |
| contrast_color | 1.4.3 Contrast; 1.4.1 Use of Color; 1.4.11 Non-text Contrast |  54 | 0.54 | 0.24 | 0.07 |
| zoom_text_size | 1.4.4 Resize Text; 1.4.10 Reflow; 1.4.12 Text Spacing |  12 | 0.50 | 0.25 | 0.00 |
| forms_errors | 3.3.1 Error Identification; 3.3.2 Labels or Instructions; 1.3.5 Identify Input Purpose |   6 | 0.33 | 0.17 | 0.00 |
| touch_target_pointer | 2.5.5 Target Size; 2.5.1 Pointer Gestures; 2.5.7 Dragging |   4 | 1.00 | 0.50 | 0.00 |
| timing | 2.2.1 Timing Adjustable |   3 | 1.00 | 1.00 | 0.00 |
| motion_animation | 2.3.3 Animation from Interactions; 2.2.2 Pause, Stop, Hide |   2 | 1.00 | 0.00 | 0.00 |
| language_reading | 3.1.x Readable; 3.2.x Predictable |   1 | 0.00 | 0.00 | 0.00 |

## By language

| lang | repos | with_a11y_issues | share | a11y_issues |
|---|---|---|---|---|
| Python | 96 |  1 | 0.01 |    1 |
| TypeScript | 89 | 13 | 0.15 | 1,518 |
| JavaScript | 46 |  4 | 0.09 |  201 |
| Go | 44 |  1 | 0.02 |   12 |
| Other | 40 |  1 | 0.03 |   42 |
| Rust | 35 |  1 | 0.03 |   13 |
| C++ | 27 |  5 | 0.19 |  140 |
| Java | 13 |  1 | 0.08 |    3 |
| C | 10 |  0 | 0.00 |    0 |

## Per repository (top 15 by accessibility issues)

| repo | n_accessibility | n_bug | closed_90d_accessibility | closed_90d_bug | not_planned_accessibility | not_planned_bug |
|---|---|---|---|---|---|---|
| microsoft/vscode | 500 | 193 | 0.68 | 0.55 | 0.13 | 0.05 |
| mui/material-ui | 147 | 189 | 0.37 | 0.64 | 0.11 | 0.01 |
| mastodon/mastodon |  42 | 200 | 0.05 | 0.96 | 0.07 | 0.16 |
| Leaflet/Leaflet |  23 | 199 | 0.30 | 0.73 | 0.00 | 0.25 |
| react/react-native |  18 |  22 | 0.06 | 0.59 | 0.28 | 0.09 |
| microsoft/monaco-editor |  15 | 189 | 0.20 | 0.39 | 0.13 | 0.05 |
| warpdotdev/warp |  13 | 199 | 0.00 | 0.35 | 0.23 | 0.36 |
| cli/cli |  12 | 196 | 0.50 | 0.71 | 0.00 | 0.10 |
| angular/angular |   8 | 200 | 0.00 | 0.47 | 0.25 | 0.08 |
| ionic-team/ionic-framework |   7 | 194 | 0.00 | 0.40 | 0.00 | 0.02 |
| nomic-ai/gpt4all |   6 | 189 | 0.00 | 0.49 | 0.00 | 0.23 |
| RocketChat/Rocket.Chat |   5 | 198 | 0.40 | 0.42 | 0.00 | 0.01 |

## By author association (repositories with both groups)

| group | assoc | issues | closed_share | closed_90d | not_planned | share_of_group |
|---|---|---|---|---|---|---|
| accessibility | Maintainer or member |  272 | 0.85 | 0.72 | 0.05 | 0.34 |
| accessibility | Outside reporter |  425 | 0.66 | 0.40 | 0.16 | 0.53 |
| accessibility | Prior contributor |  112 | 0.77 | 0.46 | 0.12 | 0.14 |
| bug | Maintainer or member |  273 | 0.72 | 0.56 | 0.06 | 0.08 |
| bug | Outside reporter | 2,697 | 0.73 | 0.54 | 0.11 | 0.78 |
| bug | Prior contributor |  505 | 0.86 | 0.62 | 0.03 | 0.15 |
