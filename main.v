module main

import os
import term
import flag

fn get_local_branches(exclude []string) ?[]string {
	result := os.execute('git branch')
	if result.exit_code == 0 {
		local_branches := result.output.split_into_lines().map(it.trim(' \n'))
		mut local_branches_to_check := []string{}
		for local_branch in local_branches {
			if local_branch !in exclude {
				local_branches_to_check << local_branch
			}
		}
		return local_branches_to_check
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
	common_parent := find_common_parent('master', branch.trim(' \n')) or { panic(err.msg) }

	temp_squash_commit := create_a_temporary_squashed_commit(branch, common_parent.trim(' \n')) or {
		panic(err.msg)
	}

	already_merged_via_squash := validation_of_squash_merged_branch('master', temp_squash_commit) or {
		panic(err.msg)
	}

	return if already_merged_via_squash { true } else { false }
}

fn remove_local_branch(branch string) ?bool {
	result := os.execute('git branch -D $branch')

	return if result.exit_code == 0 { true } else { error(result.output) }
}

struct SquashedBranch {
	name     string
	selected bool
}

const (
	tool_version     = '0.0.1'
	tool_description = 'Finds local branches that have been merged into the main branch via squash commit'
)

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application('delete_squashed_branches')
	fp.version(tool_version)
	fp.limit_free_args(0, 0)
	fp.description(tool_description)
	fp.skip_executable()
	exclude := fp.string_multi('exclude', `e`, '--exclude "my_branch_1, my_branch_2"')
	help := fp.bool('help', `h`, false, 'print usage')
	if help {
		println(fp.usage())
		exit(0)
	}
	fp.finalize() or {
		println(fp.usage())
		exit(1)
	}

	local_branches := get_local_branches(exclude) or {
		println(err.msg)
		exit(1)
	}

	// TODO
	// find main branch
	// get remote

	remote_branches := get_remote_branches() or { panic(err.msg) }

	local_branches_in_remote := distinct_branches(local_branches, remote_branches)

	squahed_branches := local_branches_in_remote.filter(fn (branch string) bool {
		return if check_if_branch_is_squashed(branch) { true } else { false }
	})

	if squahed_branches.len == 0 {
		println('There are no squashed branches to delete. Good for you!')
		print('bye bye')
		exit(0)
	}

	mut selected_squashed_branches := []SquashedBranch{}

	for b in squahed_branches {
		selected_squashed_branches << SquashedBranch{
			name: b
			selected: true
		}
	}

	for branch in selected_squashed_branches {
		println(if branch.selected { '[X] ' } else { '[ ] ' } + '$branch.name')
	}

	println(term.colorize(term.red, '\nAbove the list of the local branches, not in remote that have been merged into the main branch\n'))
	println(term.colorize(term.white, 'Rerun the comand with --exclude "my_branch_1,my_branch_2" to prevent those local branches from being deleted\n'))
	for {
		input := os.input(term.colorize(term.white, 'Type "delete" to continue with the deletion: '))
		if input == 'delete' {
			println('')
			for branch in selected_squashed_branches {
				if branch.selected {
					remove_local_branch(branch.name) or {
						println(term.colorize(term.red, 'Error deleting branch $branch.name: $err'))
						continue
					}
					println(term.colorize(term.green, '$branch.name deleted'))
				}
			}
			break
		}
	}
	println('bye bye')
}
