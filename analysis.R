# How open source handles accessibility bugs
# Reads data/issues.csv, data/repos.csv, data/wcag_categories.csv
# Writes output/*.csv, output/readme_tables.md, output/headline_numbers.txt, figures/*.png
# Run from the repository root: Rscript analysis.R

need <- c("tidyverse", "scales", "survival", "ggrepel")
for (p in need) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(tidyverse); library(scales); library(survival); library(ggrepel) })
dir.create("output", showWarnings = FALSE); dir.create("figures", showWarnings = FALSE)
theme_set(theme_minimal(base_size = 12) + theme(panel.grid.minor = element_blank(), plot.title.position = "plot"))
pal <- c(accessibility = "#d95f02", bug = "#1b9e77")

issues <- read_csv("data/issues.csv", show_col_types = FALSE) %>%
  mutate(group = factor(group, c("accessibility", "bug")), created = as.Date(created_at), year = year(created),
         state_reason = replace_na(state_reason, ""), author_association = replace_na(author_association, ""))
repos <- read_csv("data/repos.csv", show_col_types = FALSE) %>% filter(collected == 1)
cats <- read_csv("data/wcag_categories.csv", show_col_types = FALSE)

# ---- 1. Who labels accessibility at all? ---------------------------------------
repos <- repos %>% mutate(has_a11y_label = a11y_issues_total > 0, lang = fct_lump_n(language, 8))
coverage <- repos %>% summarise(repos = n(), with_a11y_issues = sum(has_a11y_label), share = mean(has_a11y_label),
                                with_10_or_more = sum(a11y_issues_total >= 10), with_bug_issues = sum(bug_issues_total > 0))
by_lang <- repos %>% group_by(lang) %>% summarise(repos = n(), with_a11y_issues = sum(has_a11y_label), share = mean(has_a11y_label),
                                                  a11y_issues = sum(a11y_issues_total), .groups = "drop") %>% arrange(desc(repos))
write_csv(coverage, "output/coverage.csv"); write_csv(by_lang, "output/coverage_by_language.csv")

top_repos <- repos %>% filter(has_a11y_label) %>% arrange(desc(a11y_issues_total)) %>%
  left_join(issues %>% filter(group == "accessibility") %>% group_by(repo) %>%
              summarise(a11y_closed_share = mean(closed), a11y_not_planned_share = mean(state_reason == "not_planned"), .groups = "drop"), by = "repo") %>%
  left_join(issues %>% filter(group == "bug") %>% group_by(repo) %>% summarise(bug_closed_share = mean(closed), .groups = "drop"), by = "repo")
write_csv(top_repos, "output/repos_with_accessibility_issues.csv")

p1 <- top_repos %>% slice_head(n = 25) %>% mutate(repo = fct_reorder(repo, a11y_issues_total)) %>%
  ggplot(aes(a11y_issues_total, repo)) +
  geom_segment(aes(x = 0.8, xend = a11y_issues_total, yend = repo), color = "grey70") +
  geom_point(aes(color = a11y_closed_share), size = 3.5) +
  scale_color_viridis_c(name = "Share closed", labels = percent, option = "mako", direction = -1, limits = c(0, 1)) +
  scale_x_log10(labels = comma) +
  labs(title = sprintf("Only %d of the %d most-starred software repositories had an accessibility-labeled issue", coverage$with_a11y_issues, coverage$repos),
       subtitle = "Issues opened January 2022 to June 2025. The 25 repositories with the most; dot color is the share of those issues closed by October 2026.",
       x = "Accessibility-labeled issues opened January 2022 to June 2025 (log scale)", y = NULL,
       caption = "GitHub search API, labels matching accessibility or a11y. Top 1,000 repositories by stars, filtered to projects that ship software.") +
  theme(legend.position = "right")
ggsave("figures/fig1_who_labels_accessibility.png", p1, width = 10, height = 7.5, dpi = 150, bg = "white")

# ---- 2. Time to close: accessibility versus bug, within the same repositories -----
# "both" = every collected issue from repositories that have at least one issue in each group. The bug sample is
# the latest 200 bug-labeled issues per repository, so bugs skew later in the window; Kaplan-Meier handles the
# shorter follow-up, and the Cox model adds opening year as a covariate. As a stricter check, "matched" keeps
# only issues opened after the later of a repository's first sampled bug and first accessibility issue.
both_repos <- issues %>% group_by(repo) %>% summarise(a = sum(group == "accessibility"), b = sum(group == "bug"), .groups = "drop") %>% filter(a > 0, b > 0) %>% pull(repo)
both <- issues %>% filter(repo %in% both_repos)
windows <- both %>% group_by(repo, group) %>% summarise(first = min(created), .groups = "drop") %>%
  pivot_wider(names_from = group, values_from = first) %>% mutate(window_start = pmax(accessibility, bug))
matched <- both %>% inner_join(windows %>% select(repo, window_start), by = "repo") %>% filter(created >= window_start)
write_csv(windows, "output/matched_windows.csv")

summ <- function(d) d %>% group_by(group) %>%
  summarise(issues = n(), repos = n_distinct(repo), closed_share = mean(closed),
            closed_30d = mean(closed_within_30d), closed_90d = mean(closed_within_90d), closed_365d = mean(closed_within_365d),
            not_planned_share = mean(state_reason == "not_planned"), duplicate_share = mean(state_reason == "duplicate"),
            still_open_share = mean(closed == 0), median_comments = median(comments), mean_reactions = mean(reactions), .groups = "drop")
km_median <- function(d) {
  s <- summary(survfit(Surv(days_to_close_or_censor, closed) ~ group, data = d))$table
  tibble(group = sub("group=", "", rownames(s)), km_median_days = s[, "median"])
}
with_km <- function(d, label) summ(d) %>% left_join(km_median(d), by = "group") %>% mutate(sample = label)
summary_tbl <- bind_rows(with_km(issues, "all collected issues"),
                         with_km(both, "repositories with both groups"),
                         with_km(both %>% filter(repo != "microsoft/vscode"), "repositories with both groups, without microsoft/vscode"),
                         with_km(matched, "matched opening windows (strict)")) %>% relocate(sample)
write_csv(summary_tbl, "output/summary_by_group.csv")
sum_both <- summary_tbl %>% filter(sample == "repositories with both groups")

# Cox models stratified by repository: the closure hazard of an accessibility issue relative to a bug in the same project
cox_row <- function(d, label) {
  m <- coxph(Surv(days_to_close_or_censor, closed) ~ group + factor(year) + strata(repo), data = d)
  ci <- exp(confint(m))["groupbug", ]
  # the model codes bug relative to accessibility, so invert to read as accessibility relative to bug
  tibble(sample = label, hazard_ratio_a11y_vs_bug = 1 / exp(coef(m))["groupbug"], lower95 = 1 / ci[2], upper95 = 1 / ci[1],
         p = summary(m)$coefficients["groupbug", 5], n = m$n, events = m$nevent, repos = n_distinct(d$repo))
}
cox_tbl <- bind_rows(cox_row(both, "repositories with both groups, year adjusted"),
                     cox_row(both %>% filter(repo != "microsoft/vscode"), "without microsoft/vscode, year adjusted"),
                     cox_row(matched, "matched opening windows (strict)"))
write_csv(cox_tbl, "output/cox_models.csv")

km_df <- function(d, label) {
  k <- survfit(Surv(days_to_close_or_censor, closed) ~ group, data = d)
  tibble(time = k$time, surv = k$surv, group = rep(sub("group=", "", names(k$strata)), k$strata)) %>%
    bind_rows(tibble(time = 0, surv = 1, group = c("accessibility", "bug"))) %>% arrange(group, time) %>% mutate(panel = label)
}
sum_novsc <- summary_tbl %>% filter(sample == "repositories with both groups, without microsoft/vscode")
kmd <- bind_rows(km_df(both, sprintf("All %d repositories that label both (median: bugs %.0f days, accessibility %.0f)", n_distinct(both$repo), sum_both$km_median_days[2], sum_both$km_median_days[1])),
                 km_df(both %>% filter(repo != "microsoft/vscode"), sprintf("Without microsoft/vscode (median: bugs %.0f days, accessibility %.0f)", sum_novsc$km_median_days[2], sum_novsc$km_median_days[1])))
p2 <- ggplot(kmd %>% filter(time <= 730), aes(time, 1 - surv, color = group)) +
  geom_step(linewidth = 1.2) +
  facet_wrap(~ panel, ncol = 2) +
  scale_color_manual(values = pal, name = NULL, labels = c("Accessibility-labeled", "Bug-labeled")) +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  scale_x_continuous(breaks = c(0, 90, 180, 365, 730)) +
  labs(title = "Share of issues closed by days since opening, within the same repositories",
       subtitle = sprintf("Kaplan-Meier on %s issues. VS Code files and closes most of the accessibility issues in the sample; take it out and the gap opens wide.", comma(nrow(both))),
       x = "Days since the issue was opened", y = "Share closed", caption = "Issues opened January 2022 to June 2025, followed to October 2026. Open issues are censored at the pull date.") +
  theme(legend.position = "top")
ggsave("figures/fig2_time_to_close.png", p2, width = 11, height = 5.5, dpi = 150, bg = "white")

# ---- 3. Per-repository comparison -------------------------------------------------
per_repo <- both %>% group_by(repo, group) %>%
  summarise(n = n(), closed_share = mean(closed), closed_90d = mean(closed_within_90d), not_planned = mean(state_reason == "not_planned"), .groups = "drop") %>%
  pivot_wider(names_from = group, values_from = c(n, closed_share, closed_90d, not_planned)) %>%
  filter(n_accessibility >= 5, n_bug >= 20) %>%
  left_join(repos %>% select(repo, stars, language), by = "repo") %>%
  mutate(gap_90d = closed_90d_bug - closed_90d_accessibility) %>% arrange(desc(n_accessibility))
write_csv(per_repo, "output/per_repo_comparison.csv")
p3 <- ggplot(per_repo, aes(closed_90d_bug, closed_90d_accessibility)) +
  geom_abline(slope = 1, intercept = 0, color = "grey60", linetype = "22") +
  geom_point(aes(size = n_accessibility), color = "#d95f02", alpha = 0.8) +
  geom_text_repel(aes(label = sub(".*/", "", repo)), size = 3, max.overlaps = 20) +
  scale_x_continuous(labels = percent, limits = c(0, 1)) + scale_y_continuous(labels = percent, limits = c(0, 1)) +
  scale_size_continuous(name = "Accessibility issues", range = c(2, 9)) +
  labs(title = "Share of issues closed within 90 days: accessibility versus bugs, project by project",
       subtitle = "Projects with at least 5 accessibility-labeled and 20 bug-labeled issues. Below the line, accessibility issues wait longer.",
       x = "Bug-labeled issues closed within 90 days", y = "Accessibility-labeled issues closed within 90 days") +
  theme(legend.position = "right")
ggsave("figures/fig3_per_repo_90d.png", p3, width = 9.5, height = 7, dpi = 150, bg = "white")

# ---- 4. What accessibility issues are about -------------------------------------
a11y <- issues %>% filter(group == "accessibility")
by_cat <- a11y %>% group_by(wcag_category) %>%
  summarise(issues = n(), share = n() / nrow(a11y), closed_share = mean(closed), closed_90d = mean(closed_within_90d),
            not_planned = mean(state_reason == "not_planned"), median_comments = median(comments), .groups = "drop") %>%
  left_join(cats %>% select(category, wcag_criteria), by = c("wcag_category" = "category")) %>% arrange(desc(issues))
write_csv(by_cat, "output/by_wcag_category.csv")
p4 <- by_cat %>% mutate(lab = ifelse(is.na(wcag_criteria), "No keyword match", str_replace_all(wcag_category, "_", " ")),
                        lab = fct_reorder(lab, issues)) %>%
  ggplot(aes(issues, lab, fill = closed_share)) + geom_col(width = 0.75) +
  geom_text(aes(label = sprintf("%d  (%.0f%% closed)", issues, 100 * closed_share)), hjust = -0.08, size = 3.2) +
  scale_fill_viridis_c(name = "Share closed", labels = percent, option = "mako", direction = -1, limits = c(0, 1)) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(title = "What the accessibility issues are about",
       subtitle = "Keyword classification of titles and first 600 characters, mapped to WCAG success criteria. Rules in data/wcag_categories.csv.",
       x = "Accessibility-labeled issues", y = NULL) + theme(legend.position = "none")
ggsave("figures/fig4_wcag_categories.png", p4, width = 9.5, height = 5.5, dpi = 150, bg = "white")

# ---- 5. Over time -----------------------------------------------------------------
by_q <- issues %>% mutate(quarter = floor_date(created, "quarter")) %>% group_by(group, quarter) %>%
  summarise(issues = n(), closed_90d = mean(closed_within_90d), .groups = "drop")
write_csv(by_q, "output/by_quarter.csv")
p5 <- ggplot(by_q, aes(quarter, closed_90d, color = group)) + geom_line(linewidth = 1.1) + geom_point(size = 2) +
  scale_color_manual(values = pal, name = NULL, labels = c("Accessibility-labeled", "Bug-labeled")) +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  labs(title = "Share closed within 90 days, by quarter the issue was opened",
       subtitle = "All collected issues. Bug-labeled issues are sampled from the most recent 200 per repository, so earlier quarters hold fewer of them.",
       x = NULL, y = "Closed within 90 days") + theme(legend.position = "top")
ggsave("figures/fig5_by_quarter.png", p5, width = 9, height = 5, dpi = 150, bg = "white")

# ---- 6. Who files them, and what happens to outsiders' reports --------------------
by_author <- both %>% mutate(assoc = case_when(author_association %in% c("MEMBER", "OWNER", "COLLABORATOR") ~ "Maintainer or member",
                                                 author_association == "CONTRIBUTOR" ~ "Prior contributor", TRUE ~ "Outside reporter")) %>%
  group_by(group, assoc) %>% summarise(issues = n(), closed_share = mean(closed), closed_90d = mean(closed_within_90d), not_planned = mean(state_reason == "not_planned"), .groups = "drop") %>%
  group_by(group) %>% mutate(share_of_group = issues / sum(issues)) %>% ungroup()
write_csv(by_author, "output/by_author_association.csv")

# ---- 7. README tables and headline numbers ----------------------------------------
md_table <- function(df, digits = 2) {
  df <- df %>% mutate(across(where(is.numeric), ~ ifelse(abs(.x) >= 1000, comma(.x, accuracy = 1), format(round(.x, digits), nsmall = 0))))
  paste0("| ", paste(names(df), collapse = " | "), " |\n|", paste(rep("---", ncol(df)), collapse = "|"), "|\n",
         paste0("| ", apply(df, 1, paste, collapse = " | "), " |", collapse = "\n"), "\n")
}
sink("output/readme_tables.md")
cat("## Summary by group\n\n"); cat(md_table(summary_tbl %>% select(sample, group, issues, repos, closed_share, closed_90d, closed_365d, not_planned_share, km_median_days, median_comments)))
cat("\n## Cox models (closure hazard, stratified by repository)\n\n"); cat(md_table(cox_tbl, 3))
cat("\n## By WCAG category\n\n"); cat(md_table(by_cat %>% select(wcag_category, wcag_criteria, issues, closed_share, closed_90d, not_planned)))
cat("\n## By language\n\n"); cat(md_table(by_lang))
cat("\n## Per repository (top 15 by accessibility issues)\n\n"); cat(md_table(per_repo %>% slice_head(n = 15) %>% select(repo, n_accessibility, n_bug, closed_90d_accessibility, closed_90d_bug, not_planned_accessibility, not_planned_bug)))
cat("\n## By author association (repositories with both groups)\n\n"); cat(md_table(by_author))
sink()
sm <- sum_both; cx <- cox_tbl[1, ]
hn <- c(
  sprintf("Repositories: %d collected; %d (%.0f%%) had at least one accessibility-labeled issue opened Jan 2022 to Jun 2025; %d had 10 or more", coverage$repos, coverage$with_a11y_issues, 100 * coverage$share, coverage$with_10_or_more),
  sprintf("Repositories with both groups: %d accessibility and %d bug issues in %d repositories", sm$issues[sm$group == "accessibility"], sm$issues[sm$group == "bug"], n_distinct(both$repo)),
  sprintf("Closed within 90 days: accessibility %.0f%%, bug %.0f%%; within a year: %.0f%% vs %.0f%%; closed by Oct 2026: %.0f%% vs %.0f%%",
          100 * sm$closed_90d[1], 100 * sm$closed_90d[2], 100 * sm$closed_365d[1], 100 * sm$closed_365d[2], 100 * sm$closed_share[1], 100 * sm$closed_share[2]),
  sprintf("Kaplan-Meier median days to close: accessibility %.0f, bug %.0f", sm$km_median_days[1], sm$km_median_days[2]),
  sprintf("Cox hazard ratio, accessibility vs bug within repository: %.2f (95%% CI %.2f to %.2f); without vscode %.2f (%.2f to %.2f)",
          cx$hazard_ratio_a11y_vs_bug, cx$lower95, cx$upper95, cox_tbl$hazard_ratio_a11y_vs_bug[2], cox_tbl$lower95[2], cox_tbl$upper95[2]),
  sprintf("Closed as not planned: accessibility %.0f%%, bug %.0f%%", 100 * sm$not_planned_share[1], 100 * sm$not_planned_share[2]),
  sprintf("Largest category: %s (%d issues, %.0f%% of accessibility issues); no keyword match: %d", by_cat$wcag_category[1], by_cat$issues[1], 100 * by_cat$share[1], by_cat$issues[by_cat$wcag_category == "other"]),
  sprintf("microsoft/vscode alone: %d of %d accessibility issues collected", sum(a11y$repo == "microsoft/vscode"), nrow(a11y)))
writeLines(hn, "output/headline_numbers.txt"); cat(hn, sep = "\n")
