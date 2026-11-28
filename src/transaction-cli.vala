/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2026 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

namespace Pamac {
	public class TransactionCli: Transaction {
		string current_line;
		string current_action;
		bool summary_shown;
		bool commit_transaction_answer;
		public bool no_confirm { get; set; }

		public TransactionCli (Database database) {
			Object (database: database);
		}

		construct {
			current_line = "";
			current_action = "";
			summary_shown = false;
			no_confirm = false;
			commit_transaction_answer = false;
			// connect to signal
			emit_action.connect (print_action);
			emit_action_progress.connect (print_action_progress);
			emit_download_progress.connect (print_download_progress);
			emit_hook_progress.connect (print_hook_progress);
			emit_script_output.connect (on_emit_script_output);
			emit_warning.connect (print_warning);
			emit_error.connect (print_error);
			// check_dbs
			var loop = new MainLoop ();
			check_dbs.begin ((obj, res) => {
				loop.quit ();
			});
			loop.run ();
		}

		// throws IOError.CANCELLED when cancellable is cancelled, after killing the command
		protected override async int run_cmd_line_async (GenericArray<string> args, string? working_directory, Cancellable cancellable) throws Error {
			var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_INHERIT);
			if (working_directory != null) {
				launcher.set_cwd (working_directory);
			}
			launcher.set_environ (Environ.get ());
			// spawnv needs a null terminated array
			GenericArray<string> args_copy = args.copy (strdup);
			args_copy.length = args_copy.length + 1;
			Subprocess process;
			try {
				process = launcher.spawnv (args_copy.data);
			} catch (Error e) {
				print_error (e.message, new GenericArray<string> ());
				return 1;
			}
			try {
				yield process.wait_async (cancellable);
			} catch (IOError.CANCELLED e) {
				process.send_signal (Posix.Signal.INT);
				process.send_signal (Posix.Signal.KILL);
				throw e;
			}
			return process.get_if_exited () ? process.get_exit_status () : 1;
		}

		int get_term_width () {
			int width = 80;
			Linux.winsize win;
			if (Linux.ioctl (Posix.STDOUT_FILENO, Linux.Termios.TIOCGWINSZ, out win) == 0) {
				width = win.ws_col;
			}
			return width;
		}

		void display_current_line () {
			if (current_line != "") {
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
				stdout.printf (current_line);
				stdout.printf ("\n");
				current_line = "";
			}
		}

		void on_emit_script_output (string line) {
			display_current_line ();
			stdout.printf (line);
			stdout.printf ("\n");
		}

		void print_action (string action) {
			display_current_line ();
			current_line = "";
			stdout.printf (action);
			stdout.printf ("\n");
		}

		void print_download_progress (string action, string status, double progress) {
			if (action == current_action) {
				current_line = status;
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
				stdout.printf (status);
			} else {
				current_action = action;
				current_line = status;
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
				stdout.printf (action);
				stdout.printf ("\n");
				stdout.printf (status);
			}
			if (progress == 1) {
				current_line = "";
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
			}
			stdout.flush ();
		}

		void print_action_progress (string action, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				display_current_line ();
			}
			int width = get_term_width () - action.char_count () - 1;
			string current_status = "[%s]".printf (status);
			if (width > current_status.length) {
				if (progress == 1) {
					current_line = "";
					stdout.printf ("%s %*s\n".printf (action, width, current_status));
				} else {
					current_line = "%s %*s".printf (action, width, current_status);
					stdout.printf (current_line);
					stdout.printf ("\r");
				}
			} else {
				current_line = "%s %s".printf (action, current_status);
				stdout.printf (current_line);
				stdout.printf ("\n");
			}
			stdout.flush ();
		}

		void print_hook_progress (string action, string details, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				display_current_line ();
				stdout.printf (action);
				stdout.printf ("\n");
			}
			int width = get_term_width () - details.char_count () - 1;
			string current_status = "[%s]".printf (status);
			stdout.printf ("%s %*s\n".printf (details, width, current_status));
		}

		void print_warning (string line) {
			display_current_line ();
			stdout.printf (line);
			stdout.printf ("\n");
		}

		void print_error (string message, GenericArray<string> details) {
			display_current_line ();
			if (details.length > 0) {
				if (details.length == 1) {
					stdout.printf ("%s: %s: %s\n", dgettext (null, "Error"), message, details[0]);
				} else {
					stdout.printf ("%s: %s:\n", dgettext (null, "Error"), message);
					foreach (unowned string detail in details) {
						stdout.printf ("%s\n", detail);
					}
				}
			} else {
				stdout.printf ("%s: %s\n", dgettext (null, "Error"), message);
			}
		}

		protected override async GenericArray<string> choose_optdeps (string pkgname, GenericArray<string> optdeps) {
			var optdeps_to_install = new GenericArray<string> ();
			if (no_confirm) {
				return optdeps_to_install;
			}
			stdout.printf ("\n");
			// print pkgs
			int num_length = optdeps.length.to_string ().length + 1;
			stdout.printf ("%s:\n".printf (dgettext (null, "Choose optional dependencies for %s").printf (pkgname)));
			int num = 1;
			foreach (unowned string name in optdeps) {
				stdout.printf ("%*s  %s\n",
								num_length, "%i:".printf (num),
								name);
				num++;
			}
			// get user input
			while (true) {
				stdout.printf ("\n");
				stdout.printf ("%s: ", dgettext (null, "Enter a selection (default=%s)").printf (dgettext (null, "none")));
				stdout.flush ();
				Posix.tcflush (stdin.fileno (), Posix.TCIFLUSH);
				string? ans = stdin.read_line ();
				if (ans == null) {
					break;
				}
				uint nb;
				uint[] numbers = {};
				// remove trailing newline
				ans = ans.replace ("\n", "");
				// just return use default
				if (ans == "") {
					break;
				} else {
					// split with commas "," and spaces " "
					string[] splitted = ans.split_set (", ");
					foreach (unowned string part in splitted) {
						// check for range
						if ("-" in part) {
							string[] splitted2 = part.split ("-", 2);
							// get all numbers in range
							uint beg_num, end_num;
							if (uint.try_parse (splitted2[0], out beg_num)) {
								if (uint.try_parse (splitted2[1], out end_num)) {
									// clamp to avoid overflow and useless iterations
									if (end_num > optdeps.length) {
										end_num = optdeps.length;
									}
									nb = beg_num;
									while (nb <= end_num) {
										if (nb >= 1 && nb <= optdeps.length) {
											numbers += nb;
										}
										nb++;
									}
								}
							}
						} else if (uint.try_parse (part, out nb)) {
							if (nb >= 1 && nb <= optdeps.length) {
								numbers += nb;
							}
						}
					}
				}
				if (numbers.length > 0) {
					foreach (uint number in numbers) {
						optdeps_to_install.add (optdeps[number -1]);
					}
					break;
				}
			}
			stdout.printf ("\n");
			return optdeps_to_install;
		}

		protected override async int choose_provider (string depend, GenericArray<string> providers) {
			if (no_confirm) {
				// choose first provider
				return 0;
			}
			// keep one entry per provider (null if not found) so that
			// the displayed numbers match the indexes in providers
			var pkgs = new GenericArray<Package?> ();
			foreach (unowned string provider in providers) {
				Package? pkg = database.get_sync_pkg (provider);
				if (pkg == null)  {
					pkg = database.get_aur_pkg (provider);
				}
				pkgs.add (pkg);
			}
			// print pkgs
			int name_length = 0;
			int version_length = 0;
			for (uint i = 0; i < providers.length; i++) {
				unowned Package? pkg = pkgs[i];
				unowned string name = pkg == null ? providers[i] : pkg.name;
				if (name.length > name_length) {
					name_length = name.length;
				}
				if (pkg != null && pkg.version.length > version_length) {
					version_length = pkg.version.length;
				}
			}
			int num_length = providers.length.to_string ().length + 1;
			stdout.printf ("%s:\n".printf (dgettext (null, "Choose a provider for %s").printf (depend)));
			for (uint i = 0; i < providers.length; i++) {
				unowned Package? pkg = pkgs[i];
				if (pkg == null) {
					stdout.printf ("%*s  %s\n",
									num_length, "%u:".printf (i + 1),
									providers[i]);
				} else {
					stdout.printf ("%*s  %-*s  %-*s  %s\n",
									num_length, "%u:".printf (i + 1),
									name_length, pkg.name,
									version_length, pkg.version,
									pkg.repo ?? "");
				}
			}
			// get user input
			while (true) {
				stdout.printf ("\n");
				stdout.printf ("%s: ", dgettext (null, "Enter a number (default=%d)").printf (1));
				stdout.flush ();
				Posix.tcflush (stdin.fileno (), Posix.TCIFLUSH);
				string? ans = stdin.read_line  ();
				if (ans == null) {
					stdout.printf ("\n");
					// use default: first provider
					return 0;
				}
				int64 nb;
				// remove trailing newline
				ans = ans.replace ("\n", "");
				// just return use default
				if (ans == "") {
					nb = 1;
				} else if (!int64.try_parse (ans, out nb)) {
					nb = 0;
				}
				if (nb >= 1 && nb <= providers.length) {
					int index = (int) nb - 1;
					stdout.printf ("\n");
					return index;
				}
			}
		}

		public bool ask_user (string question) {
			// ask user confirmation
			stdout.printf ("%s ? %s ", question, dgettext (null, "[y/N]"));
			stdout.flush ();
			Posix.tcflush (stdin.fileno (), Posix.TCIFLUSH);
			// read the whole line so nothing is left in stdin buffer for the next question
			string? ans = stdin.read_line ();
			if (ans != null) {
				// remove trailing newline and uppercase
				ans = ans.replace ("\n", "").down ();
				// just return use default
				if (ans != "") {
					if (ans == dgettext (null, "y") ||
						ans == dgettext (null, "yes") ||
						ans == "y" ||
						ans == "yes") {
						return true;
					}
				}
			}
			stdout.printf ("\n");
			return false;
		}

		protected override async bool ask_import_key (string pkgname, string key, string? owner) {
			stdout.printf ("%s.\n".printf (dgettext (null, "The PGP key %1$s is needed to verify %2$s source files").printf (key, pkgname)));
			PGPKey? pgp_key = get_pgp_key (key);
			if (pgp_key != null) {
				// give all the informations needed to decide to trust the key
				foreach (unowned string detail in pgp_key.get_details ()) {
					stdout.printf ("  %s\n", detail);
				}
				foreach (unowned string warning in pgp_key.get_warnings ()) {
					stdout.printf ("%s: %s.\n", dgettext (null, "Warning"), warning);
				}
			}
			if (no_confirm) {
				// never trust automatically a revoked key or another key than the requested one
				if (pgp_key != null && (pgp_key.revoked || !pgp_key.match_key ())) {
					return false;
				}
				return true;
			}
			string question;
			if (owner == null) {
				question = dgettext (null, "Import the PGP key");
			} else {
				question = dgettext (null, "Trust %s and import the PGP key").printf (owner);
			}
			return ask_user (question);
		}

		protected override async bool ask_edit_build_files (TransactionSummary summary) {
			show_summary (summary);
			summary_shown = true;
			if (dry_run) {
				commit_transaction_answer = false;
				return false;
			}
			if (no_confirm) {
				commit_transaction_answer = true;
				return false;
			}
			bool answer = false;
			// ask user
			stdout.printf ("%s : %s ", dgettext (null, "Edit build files"), dgettext (null, "[e]"));
			stdout.printf ("\n");
			stdout.printf ("%s ? %s ", dgettext (null, "Apply transaction"), dgettext (null, "[e/y/N]"));
			stdout.flush ();
			Posix.tcflush (stdin.fileno (), Posix.TCIFLUSH);
			// read the whole line so nothing is left in stdin buffer for the next question
			string? ans = stdin.read_line ();
			if (ans != null) {
				// remove trailing newline and uppercase
				ans = ans.replace ("\n", "").down ();
				// just return use default
				if (ans != "") {
					if (ans == dgettext (null, "y") ||
						ans == dgettext (null, "yes") ||
						ans == "y" ||
						ans == "yes") {
						commit_transaction_answer = true;
					} else if (ans == dgettext (null, "e") ||
								ans == "e") {
						answer = true;
					}
				}
			}
			stdout.printf ("\n");
			return answer;
		}

		// the reason why a package is in the summary, displayed in place of the installed version
		string get_summary_reason (TransactionSummary summary, Package pkg) {
			SummaryItem? item = summary.get_item (pkg);
			if (item == null || item.related == null) {
				return "";
			}
			unowned string related = item.related;
			switch (item.reason) {
				case SummaryReason.DEPENDENCY:
					return "(%s: %s)".printf (dgettext (null, "Required By"), related);
				case SummaryReason.REPLACE:
					return "(%s: %s)".printf (dgettext (null, "Replaces"), related);
				case SummaryReason.CONFLICT:
					return "(%s: %s)".printf (dgettext (null, "Conflicts With"), related);
				case SummaryReason.DEPENDS_ON_REMOVED:
					return "(%s: %s)".printf (dgettext (null, "Depends On"), related);
				case SummaryReason.ORPHAN:
					return "(%s: %s)".printf (dgettext (null, "Orphan Of"), related);
				default:
					return "";
			}
		}

		void print_summary_line (string name, int name_length, string version, int version_length,
								string details, int details_length, string repo, int repo_length, string size) {
			// translations strings need to be manually aligned
			var str_builder = new StringBuilder ("  %-*s  %-*s  ".printf (name_length, name, version_length, version));
			str_builder.append (details);
			int space_count = details.char_count ();
			while (space_count < details_length) {
				str_builder.append (" ");
				space_count++;
			}
			str_builder.append ("  %-*s  %s".printf (repo_length, repo, size));
			stdout.printf ("%s\n", str_builder.str.chomp ());
		}

		void show_summary (TransactionSummary summary) {
			uint64 rsize = 0;
			// installed_size_delta only counts the alpm packages, removals included
			int64 isize = summary.installed_size_delta;
			int name_length = 0;
			int version_length = 0;
			int details_length = 0;
			int repo_length = 0;
			GenericArray<Package>[] lists = {summary.to_upgrade, summary.to_reinstall, summary.to_install,
											summary.to_build, summary.to_downgrade, summary.to_remove,
											summary.conflicts_to_remove};
			// first pass to compute strings length
			foreach (unowned GenericArray<Package> list in lists) {
				foreach (unowned Package pkg in list) {
					name_length = int.max (name_length, pkg.name.length);
					version_length = int.max (version_length, pkg.version.length);
					unowned string? repo = pkg.repo;
					if (repo != null) {
						repo_length = int.max (repo_length, repo.length);
					}
					details_length = int.max (details_length, get_summary_reason (summary, pkg).char_count ());
				}
			}
			// the installed version is displayed for these ones
			foreach (unowned GenericArray<Package> list in new GenericArray<Package>[] {summary.to_upgrade, summary.to_downgrade, summary.to_build}) {
				foreach (unowned Package pkg in list) {
					unowned string? installed_version = pkg.installed_version;
					if (installed_version != null) {
						details_length = int.max (details_length, installed_version.char_count () + 2); // because of (%s)
					}
				}
			}
			foreach (unowned Package pkg in summary.to_remove) {
				rsize += pkg.installed_size;
				if (pkg is AlpmPackage) {
					isize += (int64) pkg.installed_size;
				}
			}
			foreach (unowned Package pkg in summary.conflicts_to_remove) {
				rsize += pkg.installed_size;
				if (pkg is AlpmPackage) {
					isize += (int64) pkg.installed_size;
				}
			}
			foreach (unowned Package pkg in summary.to_install) {
				if (!(pkg is AlpmPackage)) {
					// snaps and flatpaks
					isize += (int64) pkg.installed_size;
				}
			}
			// second pass to print details
			stdout.printf ("\n");
			if (summary.to_upgrade.length != 0) {
				stdout.printf (dgettext (null, "To upgrade") + " (%u):\n".printf (summary.to_upgrade.length));
				foreach (unowned Package pkg in summary.to_upgrade) {
					print_summary_line (pkg.name, name_length, pkg.version, version_length,
										"(%s)".printf (pkg.installed_version), details_length,
										pkg.repo ?? "", repo_length,
										pkg.download_size == 0 ? "" : format_size (pkg.download_size));
				}
			}
			if (summary.to_reinstall.length != 0) {
				stdout.printf (dgettext (null, "To reinstall") + " (%u):\n".printf (summary.to_reinstall.length));
				foreach (unowned Package pkg in summary.to_reinstall) {
					print_summary_line (pkg.name, name_length, pkg.version, version_length,
										"", details_length,
										pkg.repo ?? "", repo_length,
										pkg.download_size == 0 ? "" : format_size (pkg.download_size));
				}
			}
			if (summary.to_install.length != 0) {
				stdout.printf (dgettext (null, "To install") + " (%u):\n".printf (summary.to_install.length));
				foreach (unowned Package pkg in summary.to_install) {
					print_summary_line (pkg.name, name_length, pkg.version, version_length,
										get_summary_reason (summary, pkg), details_length,
										pkg.repo ?? "", repo_length,
										pkg.download_size == 0 ? "" : format_size (pkg.download_size));
				}
			}
			if (summary.to_build.length != 0) {
				stdout.printf (dgettext (null, "To build") + " (%u):\n".printf (summary.to_build.length));
				foreach (unowned Package pkg in summary.to_build) {
					string details;
					if (pkg.installed_version != null && pkg.installed_version != pkg.version) {
						details = "(%s)".printf (pkg.installed_version);
					} else {
						details = get_summary_reason (summary, pkg);
					}
					print_summary_line (pkg.name, name_length, pkg.version, version_length,
										details, details_length,
										pkg.repo ?? "", repo_length, "");
				}
			}
			if (summary.to_downgrade.length != 0) {
				stdout.printf (dgettext (null, "To downgrade") + " (%u):\n".printf (summary.to_downgrade.length));
				foreach (unowned Package pkg in summary.to_downgrade) {
					print_summary_line (pkg.name, name_length, pkg.version, version_length,
										"(%s)".printf (pkg.installed_version), details_length,
										pkg.repo ?? "", repo_length,
										pkg.download_size == 0 ? "" : format_size (pkg.download_size));
				}
			}
			if (summary.to_remove.length != 0 || summary.conflicts_to_remove.length != 0) {
				stdout.printf (dgettext (null, "To remove") + " (%u):\n".printf (summary.to_remove.length + summary.conflicts_to_remove.length));
				foreach (unowned Package pkg in summary.to_remove) {
					print_summary_line (pkg.name, name_length, pkg.version, version_length,
										get_summary_reason (summary, pkg), details_length,
										pkg.repo ?? "", repo_length, "");
				}
				foreach (unowned Package pkg in summary.conflicts_to_remove) {
					print_summary_line (pkg.name, name_length, pkg.version, version_length,
										get_summary_reason (summary, pkg), details_length,
										pkg.repo ?? "", repo_length, "");
				}
			}
			stdout.printf ("\n");
			if (summary.download_size > 0) {
				stdout.printf ("%s: %s\n", dgettext (null, "Total download size"), format_size (summary.download_size));
			}
			if (isize > 0) {
				stdout.printf ("%s: %s\n", dgettext (null, "Total installed size"), format_size (isize));
			} else if (isize < 0) {
				stdout.printf ("%s: -%s\n", dgettext (null, "Total installed size"), format_size (isize.abs ()));
			}
			if (rsize > 0) {
				stdout.printf ("%s: %s\n", dgettext (null, "Total removed size"), format_size (rsize));
			}
			stdout.printf ("\n");
		}

		protected override async bool ask_commit (TransactionSummary summary) {
			if (summary_shown) {
				return commit_transaction_answer;
			} else {
				show_summary (summary);
			}
			if (dry_run) {
				return false;
			}
			if (no_confirm) {
				return true;
			}
			return ask_user (dgettext (null, "Apply transaction"));
		}

		void ask_view_diff (string pkgname) {
			string diff_path = Path.build_filename (database.get_real_aur_build_dir (), pkgname, "diff");
			var diff_file = File.new_for_path (diff_path);
			if (diff_file.query_exists ()) {
				if (ask_user (dgettext (null, "View %s build files diff").printf (pkgname))) {
					string[] cmds = {};
					unowned string? editor = Environment.get_variable ("EDITOR");
					if (editor == null || editor == "nano") {
						cmds += "nano";
						cmds += "-v";
					} else {
						// support args in EDITOR
						foreach (unowned string str in editor.split (" ")) {
							cmds += str;
						}
					}
					cmds += diff_path;
					try {
						var process = new Subprocess.newv (cmds, SubprocessFlags.STDIN_INHERIT);
						process.wait ();
					} catch (Error e) {
						warning (e.message);
					}
				}
			}
		}

		async void edit_single_build_files (string pkgname) {
			GenericArray<string> files = yield get_build_files_async (pkgname);
			if (files.length > 0) {
				string[] cmds = {};
				unowned string? editor = Environment.get_variable ("EDITOR");
				if (editor == null || editor == "nano") {
					cmds += "nano";
					cmds += "-i";
				} else {
					// support args in EDITOR
					foreach (unowned string str in editor.split (" ")) {
						cmds += str;
					}
				}
				foreach (unowned string file in files) {
					cmds += file;
				}
				try {
					var process = new Subprocess.newv (cmds, SubprocessFlags.STDIN_INHERIT);
					yield process.wait_async ();
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		protected override async void edit_build_files (GenericArray<string> pkgnames) {
			if (pkgnames.length == 1) {
				ask_view_diff (pkgnames[0]);
				yield edit_single_build_files (pkgnames[0]);
			} else {
				foreach (unowned string pkgname in pkgnames) {
					ask_view_diff (pkgname);
					if (ask_user (dgettext (null, "Edit %s build files").printf (pkgname))) {
						yield edit_single_build_files (pkgname);
					}
				}
			}
		}
	}
}
