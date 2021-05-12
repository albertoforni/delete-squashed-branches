module main

import os
import term
import term.ui as tui

fn get_local_branches() ?[]string {
	result := os.execute('git branch')
	if result.exit_code == 0 {
		return result.output.split_into_lines().map(it.trim(' \n'))
	} else {
		return error(result.output)
	}
}

fn get_remote_branches() ?[]string {
	result := os.execute('git branch -r')
	if result.exit_code == 0 {
		return result.output.split_into_lines().map(fn (branch string) string {
			return branch.replace('origin/', '').trim(' \n')
		})
	} else {
		return error(result.output)
	}
}

fn distinct_branches(local_branches []string, remote_branches []string) []string {
	return remote_branches.filter(it in local_branches)
}

fn find_common_parent(main string, branch string) ?string {
	result := os.execute('git merge-base $main $branch')

	return if result.exit_code == 0 { result.output } else { error(result.output) }
}

fn create_a_temporary_squashed_commit(branch string, ancestor string) ?string {
	result := os.execute('git commit-tree $(git rev-parse $branch^{tree}) -p $ancestor -m "temporary tree object"')

	return if result.exit_code == 0 { result.output } else { error(result.output) }
}

fn validation_of_squash_merged_branch(main string, temp_tree string) ?bool {
	result := os.execute('git cherry $main $temp_tree')

	return if result.exit_code == 0 {
		result.output.trim(' \n\r')[0] == `-`
	} else {
		error(result.output)
	}
}

fn check_if_branch_is_squashed(branch string) bool {
	common_parent := find_common_parent('master', branch.trim(' \n')) or { panic(err) }

	temp_squash_commit := create_a_temporary_squashed_commit(branch, common_parent.trim(' \n')) or {
		panic(err)
	}

	already_merged_via_squash := validation_of_squash_merged_branch('master', temp_squash_commit) or {
		panic(err)
	}

	return if already_merged_via_squash { true } else { false }
}

struct SquashedBranch {
	name     string
	selected bool
}

fn main_() []SquashedBranch {
	local_branches := get_local_branches() or {
		panic(err)
		// TODO exit with non-zero code
	}

	// TODO
	// find main branch
	// get remote

	remote_branches := get_remote_branches() or { panic(err) }

	local_branches_in_remote := distinct_branches(local_branches, remote_branches)
	println(term.colorize(term.white, 'Local branches found in remote'))
	println(term.colorize(term.white, 'Tab to move'))
	println(term.colorize(term.white, 'Space to toggle'))
	println(term.colorize(term.white, 'Enter to delete the selected branches'))
	println(term.colorize(term.white, 'Esc to exit without making any change'))

	squahed_branches := local_branches_in_remote.filter(fn (branch string) bool {
		return if check_if_branch_is_squashed(branch) { true } else { false }
	})

	mut selected_squashed_branches := []SquashedBranch{}

	for b in squahed_branches {
		selected_squashed_branches << SquashedBranch{
			name: b
			selected: true
		}
	}

	mut cursor := 0
	for i, branch in selected_squashed_branches {
		println(if cursor == i { '->' } else { '  ' } +
			if branch.selected { ' [X] ' } else { ' [ ] ' } + '$branch.name')
	}

	return selected_squashed_branches
}

struct App {
mut:
	tui               &tui.Context = 0
	squashed_branches []SquashedBranch
	cursor            int
}

fn init(x voidptr) {
	mut app := &App(x)
	app.squashed_branches = main_()
}

fn event(e &tui.Event, x voidptr) {
	mut app := &App(x)
	match e.typ {
		.key_down {
			match e.code {
				.escape {
					exit(0)
				}
				.tab {
					cursor := if e.modifiers == .shift { app.cursor - 1 } else { app.cursor + 1 }
					if cursor < 0 {
						app.cursor = app.squashed_branches.len - 1
					} else if cursor == app.squashed_branches.len {
						app.cursor = 0
					} else {
						app.cursor = cursor
					}
				}
				else {}
			}
		}
		else {}
	}
}

fn frame(x voidptr) {
	mut app := &App(x)

	app.tui.clear()
	for i, branch in app.squashed_branches {
		app.tui.set_color(r: 255, g: 255, b: 255)
		app.tui.draw_text(0, i, if app.cursor == i { '->' } else { '  ' } +
			if branch.selected { ' [X] ' } else { ' [ ] ' } + '$branch.name')
	}
	app.tui.reset()
	app.tui.flush()
}

mut app := &App{}
app.tui = tui.init(
	user_data: app
	init_fn: init
	event_fn: event
	frame_fn: frame
	hide_cursor: true
)
app.tui.run() ?
