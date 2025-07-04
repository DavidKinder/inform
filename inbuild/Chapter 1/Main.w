[Main::] Main.

A command-line interface for Inbuild functions which are not part of the
normal operation of the Inform compiler.

@h Settings variables.
The following will be set at the command line.

=
pathname *path_to_inbuild = NULL;

int inbuild_task = INSPECT_TTASK;
pathname *path_to_tools = NULL;
int dry_run_mode = FALSE, build_trace_mode = FALSE, confirmed = FALSE;
int contents_of_used = FALSE, recursive = FALSE;
int JSON_file_format = FALSE;
filename *JSON_file_to_output = NULL;
inbuild_nest *destination_nest = NULL;
inbuild_registry *selected_registry = NULL;
text_stream *filter_text = NULL;
pathname *preprocess_HTML_destination = NULL;
text_stream *preprocess_HTML_app = NULL;
inbuild_copy *to_install = NULL, *to_uninstall = NULL, *to_modernise = NULL;
filename *documentation_source = NULL;
pathname *documentation_set = NULL;
filename *documentation_sitemap = NULL;
pathname *documentation_dest = NULL;

typedef struct markdown_settings_struct {
	struct filename *from;
	struct filename *to;
	struct pathname *from_dir;
	struct pathname *to_dir;
	struct filename *model;
	struct markdown_variation *variation;
} markdown_settings_struct;

markdown_settings_struct markdown_settings = { NULL, NULL, NULL, NULL, NULL, NULL };

@h Main routine.
When Inbuild is called at the command line, it begins at |main|, like all C
programs.

Inbuild manages "copies", which are instances of programs or resources found
somewhere in the file system. The copies which it acts on in a given run are
called "targets". The task of |main| is to read the command-line arguments,
set the following variables as needed, and produce a list of targets to work
on; then to carry out that work, and then shut down again.

=
int main(int argc, char **argv) {
    @<Start up the modules@>;
	@<Read the command line@>;
	CommandLine::play_back_log();
	@<Complete the list of targets@>;
	pathname *P = Nests::get_location(Supervisor::internal());
	if (P == NULL) {
		P = Pathnames::down(NULL, I"inform7");
		P = Pathnames::down(P, I"Internal");
	}
	Pathnames::set_path_to_LP_resources(P);
	if (to_install) @<Perform an extension installation@>
	else if (to_uninstall) @<Perform an extension uninstallation@>
	else if (to_modernise) @<Perform an extension modernisation@>
	else if ((markdown_settings.from) || (markdown_settings.from_dir)) @<Make HTML@>
	else if (documentation_set) @<Document from a set@>
	else if (documentation_source) @<Document from a file@>
	else @<Act on the targets@>;
	@<Shut down the modules@>;
	if (Errors::have_occurred()) return 1;
	return 0;
}

@<Start up the modules@> =
	Foundation::start(argc, argv); /* must be started first */
	WordsModule::start();
	SyntaxModule::start();
	HTMLModule::start();
	ArchModule::start();
	SupervisorModule::start();

@ Targets can arise in three ways:
(1) They can be specified at the command line, either as bare names of files
or paths, or with |-contents-of D| for a directory |D|. By the time the code
in this paragraph runs, those targets are already in the list.
(2) They can be specified by a search request |-matching R| where |R| is a
list of requirements to match. We now add anything found that way. (We didn't
do so when reading the command line because at that time the search path for
nests did not yet exist: it is created when |Supervisor::optioneering_complete|
is called.)
(3) One copy is always special to Inbuild: the "project", usually an Inform
project bundle with a pathname like |Counterfeit Monkey.inform|. We go
through a little dance with |Supervisor::optioneering_complete| to ensure that
if a project is already in the target list, Inbuild will use that; and if not,
but the user has specified a project to Inbuild already with |-project| (a
command-line option recognised by |inform7| but not by us), then we add that
to the target list. Tne net result is that however the user indicates interest
in an Inform project bundle, it becomes both the Inbuild current project, and
also a member of our target list. It follows that we cannot have two project
bundles in the target list, because they cannot both be the current project;
and to avoid the user being confused when only one is acted on, we throw an
error in this case.

@<Complete the list of targets@> =
	linked_list *L = Main::list_of_targets();
	inbuild_copy *D = NULL, *C; int others_exist = FALSE;
	LOOP_OVER_LINKED_LIST(C, inbuild_copy, L)
		if ((C->edition->work->genre == project_bundle_genre) ||
			(C->edition->work->genre == project_file_genre))
			D = C;
		else
			others_exist = TRUE;
	if ((others_exist == FALSE) && (D)) {
		if (D->location_if_path) Supervisor::set_I7_bundle(D->location_if_path);
		if (D->location_if_file) Supervisor::set_I7_source(D->location_if_file);
	}
	if ((LinkedLists::len(unsorted_nest_list) == 0) ||
		((others_exist == FALSE) && (D))) {
		SVEXPLAIN(1, "(in absence of explicit -internal, inventing -internal %p)\n",
			Supervisor::default_internal_path());
		if (path_to_tools) SVEXPLAIN(2, "(note that -tools is %p)\n", path_to_tools);
		Supervisor::add_nest(
			Supervisor::default_internal_path(), INTERNAL_NEST_TAG);
	}
	Supervisor::optioneering_complete(D, FALSE, &Main::load_preform);
	inform_project *proj;
	LOOP_OVER(proj, inform_project)
		Main::add_target(proj->as_copy);
	int count = 0;
	LOOP_OVER_LINKED_LIST(C, inbuild_copy, L)
		if ((C->edition->work->genre == project_bundle_genre) ||
			(C->edition->work->genre == project_file_genre))
			count++;
	if ((count > 1) && (inbuild_task != INSPECT_TTASK))
		Errors::with_text("can only work on one project bundle at a time", NULL);
	if (Str::len(filter_text) > 0) Main::add_search_results_as_targets(filter_text);

@<Perform an extension installation@> =
	Supervisor::go_operational();
	int use = SHELL_METHODOLOGY;
	if (dry_run_mode) use = DRY_RUN_METHODOLOGY;
	ExtensionInstaller::install(to_install, confirmed, path_to_inbuild, use);

@<Perform an extension uninstallation@> =
	Supervisor::go_operational();
	int use = SHELL_METHODOLOGY;
	if (dry_run_mode) use = DRY_RUN_METHODOLOGY;
	ExtensionInstaller::uninstall(to_uninstall, confirmed, path_to_inbuild, use);

@<Perform an extension modernisation@> =
	Supervisor::go_operational();
	int use = SHELL_METHODOLOGY;
	if (dry_run_mode) use = DRY_RUN_METHODOLOGY;
	ExtensionInstaller::modernise(to_modernise, confirmed, path_to_inbuild, use);

@<Make HTML@> =
	if (markdown_settings.from) {
		RTPPages::make_one(markdown_settings.model, markdown_settings.from,
			markdown_settings.to, markdown_settings.variation);
	} else if (markdown_settings.from_dir) {
		RTPPages::work_through_directory(markdown_settings.model,
			markdown_settings.from_dir, markdown_settings.to_dir,
			markdown_settings.variation);
	}

@<Document from a file@> =
	if (documentation_dest == NULL)
		Errors::fatal("need to specify '-document-to' directory");
	compiled_documentation *cd = DocumentationCompiler::compile_from_file(
		documentation_source, NULL, documentation_sitemap);
	if (cd) DocumentationRenderer::as_HTML(documentation_dest, cd, NULL, NULL);

@<Document from a set@> =
	if (documentation_dest == NULL)
		Errors::fatal("need to specify '-document-to' directory");
	compiled_documentation *cd = DocumentationCompiler::compile_from_path(
		documentation_set, NULL, documentation_sitemap);
	if (cd) DocumentationRenderer::as_HTML(documentation_dest, cd, NULL, NULL);

@ We make the function call |Supervisor::go_operational| to signal to |inbuild|
that we want to start work now.

@<Act on the targets@> =
	Supervisor::go_operational();
	int use = SHELL_METHODOLOGY;
	if (dry_run_mode) use = DRY_RUN_METHODOLOGY;
	build_methodology *BM;
	if (path_to_tools) BM = BuildMethodology::new(path_to_tools, FALSE, use);
	else BM = BuildMethodology::new(Pathnames::up(path_to_inbuild), TRUE, use);
	if (build_trace_mode) IncrementalBuild::enable_trace();
	JSON_value *obj = NULL;
	if (JSON_file_format) obj = JSON::new_object();
	linked_list *L = Main::list_of_targets();
	inbuild_copy *C;
	LOOP_OVER_LINKED_LIST(C, inbuild_copy, L)
		@<Carry out the required task on the copy C@>;
	if (obj) {
		Main::validate_JSON(obj);
		if (JSON_file_to_output) {
			text_stream J;
			if (STREAM_OPEN_TO_FILE(&J, JSON_file_to_output, UTF8_ENC) == FALSE)
				Errors::fatal_with_file("unable to open JSON file for output: %f",
					JSON_file_to_output);
			JSON::encode(&J, obj);
			STREAM_CLOSE(&J);
		} else {
			JSON::encode(STDOUT, obj);
		}
	}

@ The list of possible tasks is as follows; they basically all correspond to
utility functions in the //supervisor// module, which we call.

@e INSPECT_TTASK from 1
@e GRAPH_TTASK
@e USE_NEEDS_TTASK
@e BUILD_NEEDS_TTASK
@e USE_LOCATE_TTASK
@e BUILD_LOCATE_TTASK
@e ARCHIVE_TTASK
@e ARCHIVE_TO_TTASK
@e USE_MISSING_TTASK
@e BUILD_MISSING_TTASK
@e BUILD_TTASK
@e REBUILD_TTASK
@e COPY_TO_TTASK
@e SYNC_TO_TTASK
@e DOCUMENT_TTASK
@e MODERNISE_TTASK

@<Carry out the required task on the copy C@> =
	text_stream *OUT = STDOUT;
	switch (inbuild_task) {
		case INSPECT_TTASK: Copies::inspect(OUT, obj, C); break;
		case GRAPH_TTASK: Copies::show_graph(OUT, C); break;
		case USE_NEEDS_TTASK: Copies::show_needs(OUT, C, TRUE, FALSE); break;
		case BUILD_NEEDS_TTASK: Copies::show_needs(OUT, C, FALSE, FALSE); break;
		case USE_LOCATE_TTASK: Copies::show_needs(OUT, C, TRUE, TRUE); break;
		case BUILD_LOCATE_TTASK: Copies::show_needs(OUT, C, FALSE, TRUE); break;
		case ARCHIVE_TTASK: {
			inform_project *proj;
			int c = 0;
			LOOP_OVER(proj, inform_project) {
				c++;
				destination_nest = Projects::materials_nest(proj);
			}
			if (c == 0)
				Errors::with_text("no -project in use, so ignoring -archive", NULL);
			else if (c > 1)
				Errors::with_text("multiple projects in use, so ignoring -archive", NULL);
			else 
				Copies::archive(OUT, C, destination_nest, BM);
			break;
		}
		case ARCHIVE_TO_TTASK: Copies::archive(OUT, C, destination_nest, BM); break;
		case USE_MISSING_TTASK: Copies::show_missing(OUT, C, TRUE); break;
		case BUILD_MISSING_TTASK: Copies::show_missing(OUT, C, FALSE); break;
		case BUILD_TTASK: Copies::build(OUT, C, BM); break;
		case REBUILD_TTASK: Copies::rebuild(OUT, C, BM); break;
		case COPY_TO_TTASK: Copies::copy_to(C, destination_nest, FALSE, BM); break;
		case SYNC_TO_TTASK: Copies::copy_to(C, destination_nest, TRUE, BM); break;
		case DOCUMENT_TTASK:
			if (documentation_dest == NULL)
				Errors::fatal("need to specify '-document-to' directory");
			Copies::document(C, documentation_dest, documentation_sitemap); break;
		case MODERNISE_TTASK: Copies::modernise(OUT, C); break;
	}

@<Shut down the modules@> =
	ArchModule::end();
	SupervisorModule::end();
	HTMLModule::end();
	SyntaxModule::end();
	WordsModule::end();
	Foundation::end(); /* must be ended last */

@ Preform is the crowning jewel of the |words| module, and parses excerpts of
natural-language text against a "grammar". The |inform7| executable makes very
heavy-duty use of Preform, and we can use that too provided we have access to
the English Preform syntax file stored inside the core Inform distribution,
that is, in the |-internal| area.

But suppose we can't get that? Well, then we fall back on a much coarser
grammar, which simply breaks down source text into sentences, headings and so
on. That grammar is stored in a file called |Syntax.preform| inside the
installation of Inbuild, which is why we need to have worked out
|path_to_inbuild| (the pathname at which we are installed) already. Once the
following is run, Preform is ready for use.

=
int Main::load_preform(inform_language *L) {
	if (Supervisor::dash_internal_was_used()) {
		filename *F = Filenames::in(Languages::path_to_bundle(L), I"Syntax.preform");
		return LoadPreform::load(F, L);
	} else {
		pathname *P = Pathnames::down(path_to_inbuild, I"Tangled");
		filename *S = Filenames::in(P, I"Syntax.preform");
		return LoadPreform::load(S, NULL);
	}
}

@h Target list.
This where we keep the list of targets, in which no copy occurs more than
once. The following code runs quadratically in the number of targets, but for
Inbuild this number is never likely to be more than about 100 at a time.

=
linked_list *targets = NULL; /* of |inbuild_copy| */

void Main::add_target(inbuild_copy *to_add) {
	if (targets == NULL) targets = NEW_LINKED_LIST(inbuild_copy);
	int found = FALSE;
	inbuild_copy *C;
	LOOP_OVER_LINKED_LIST(C, inbuild_copy, targets)
		if (C == to_add)
			found = TRUE;
	if (found == FALSE) ADD_TO_LINKED_LIST(to_add, inbuild_copy, targets);
}

@ The following sorts the list of targets before returning it. This is partly
to improve the quality of the output of |-inspect|, but also to make the
behaviour of //inbuild// more predictable across platforms -- the raw target
list tends to be in order of discovery of the copies, which in turn depends on
the order in which filenames are read from a directory listing.

=
linked_list *Main::list_of_targets(void) {
	if (targets == NULL) targets = NEW_LINKED_LIST(inbuild_copy);
	int no_entries = LinkedLists::len(targets);
	if (no_entries == 0) return targets;
	inbuild_copy **sorted_targets =
		Memory::calloc(no_entries, sizeof(inbuild_copy *), RESULTS_SORTING_MREASON);
	int i=0;
	inbuild_copy *C;
	LOOP_OVER_LINKED_LIST(C, inbuild_copy, targets) sorted_targets[i++] = C;
	qsort(sorted_targets, (size_t) no_entries, sizeof(inbuild_copy *), Copies::cmp);
	linked_list *result = NEW_LINKED_LIST(inbuild_copy);
	for (int i=0; i<no_entries; i++)
		ADD_TO_LINKED_LIST(sorted_targets[i], inbuild_copy, result);
	Memory::I7_array_free(sorted_targets, RESULTS_SORTING_MREASON,
		no_entries, sizeof(inbuild_copy *));
	return result;
}

void Main::add_search_results_as_targets(text_stream *req_text) {	
	TEMPORARY_TEXT(errors)
	inbuild_requirement *req = Requirements::from_text(req_text, errors);
	if (Str::len(errors) > 0) {
		Errors::with_text("requirement malformed: %S", errors);
	} else {
		linked_list *L = NEW_LINKED_LIST(inbuild_search_result);
		Nests::search_for(req, Supervisor::shared_nest_list(), L);
		inbuild_search_result *R;
		LOOP_OVER_LINKED_LIST(R, inbuild_search_result, L)
			Main::add_target(R->copy);
	}
	DISCARD_TEXT(errors)
}

void Main::add_directory_contents_targets(pathname *P) {
	linked_list *L = Directories::listing(P);
	text_stream *entry;
	LOOP_OVER_LINKED_LIST(entry, text_stream, L) {
		TEMPORARY_TEXT(FILENAME)
		WRITE_TO(FILENAME, "%p%c%S", P, FOLDER_SEPARATOR, entry);
		Main::add_file_or_path_as_target(FILENAME, FALSE);
		DISCARD_TEXT(FILENAME)
	}
}

inbuild_copy *Main::file_or_path_to_copy(text_stream *arg, int throwing_error) {
	TEMPORARY_TEXT(ext)
	int pos = Str::len(arg) - 1, dotpos = -1;
	while (pos >= 0) {
		inchar32_t c = Str::get_at(arg, pos);
		if (Platform::is_folder_separator(c)) break;
		if (c == '.') dotpos = pos;
		pos--;
	}
	if (dotpos >= 0)
		Str::substr(ext, Str::at(arg, dotpos+1), Str::end(arg));
	int directory_status = NOT_APPLICABLE;
	if (Platform::is_folder_separator(Str::get_last_char(arg))) {
		Str::delete_last_character(arg);
		directory_status = TRUE;
	}
	inbuild_copy *C = NULL;
	inbuild_genre *G;
	LOOP_OVER(G, inbuild_genre)
		if (C == NULL)
			VOID_METHOD_CALL(G, GENRE_CLAIM_AS_COPY_MTID, &C, arg, ext, directory_status);
	DISCARD_TEXT(ext)
	if (C == NULL) {
		if (throwing_error) Errors::with_text("unable to identify '%S'", arg);
		return NULL;
	}
	return C;
}

void Main::add_file_or_path_as_target(text_stream *arg, int throwing_error) {
	int is_folder = Platform::is_folder_separator(Str::get_last_char(arg));
	inbuild_copy *C = Main::file_or_path_to_copy(arg, throwing_error);
	if (C) {
		Main::add_target(C);
	} else if ((recursive) && (is_folder)) {
		pathname *P = Pathnames::from_text(arg);
		linked_list *L = Directories::listing(P);
		text_stream *entry;
		LOOP_OVER_LINKED_LIST(entry, text_stream, L) {
			TEMPORARY_TEXT(FILENAME)
			WRITE_TO(FILENAME, "%p%c%S", P, FOLDER_SEPARATOR, entry);
			Main::add_file_or_path_as_target(FILENAME, throwing_error);
			DISCARD_TEXT(FILENAME)
		}
	}
}

@h Command line.
Note the call below to |Supervisor::declare_options|, which adds a whole lot of
other options to the selection defined here.

@d PROGRAM_NAME "inbuild"

@e BUILD_CLSW
@e REBUILD_CLSW
@e GRAPH_CLSW
@e USE_NEEDS_CLSW
@e BUILD_NEEDS_CLSW
@e USE_LOCATE_CLSW
@e BUILD_LOCATE_CLSW
@e USE_MISSING_CLSW
@e BUILD_MISSING_CLSW
@e ARCHIVE_CLSW
@e ARCHIVE_TO_CLSW
@e INSPECT_CLSW
@e DRY_CLSW
@e BUILD_TRACE_CLSW
@e TOOLS_CLSW
@e CONTENTS_OF_CLSW
@e RECURSIVE_CLSW
@e MATCHING_CLSW
@e COPY_TO_CLSW
@e SYNC_TO_CLSW
@e VERSIONS_IN_FILENAMES_CLSW
@e VERIFY_REGISTRY_CLSW
@e BUILD_REGISTRY_CLSW
@e PREPROCESS_HTML_CLSW
@e PREPROCESS_HTML_TO_CLSW
@e PREPROCESS_APP_CLSW
@e REPAIR_CLSW
@e RESULTS_CLSW
@e CONFIRMED_CLSW
@e VERBOSE_CLSW
@e VERBOSITY_CLSW
@e JSON_CLSW
@e MODERNISE_CLSW

@e APP_MANAGEMENT_SUITE_CLSG
@e INSTALL_CLSW
@e UNINSTALL_CLSW
@e MODERNISER_CLSW

@e DOCUMENTATION_SUITE_CLSG

@e DOCUMENT_CLSW
@e DOCUMENT_FROM_CLSW
@e DOCUMENT_SET_CLSW
@e DOCUMENT_SITEMAP_CLSW
@e DOCUMENT_TO_CLSW

@e MARKDOWN_SUITE_CLSG

@e MARKDOWN_FROM_CLSW
@e MARKDOWN_TO_CLSW
@e MARKDOWN_FROM_DIR_CLSW
@e MARKDOWN_TO_DIR_CLSW
@e MARKDOWN_MODEL_CLSW
@e MARKDOWN_VARIATION_CLSW

@<Read the command line@> =	
	CommandLine::declare_heading(
		U"[[Purpose]]\n\n"
		U"usage: inbuild [-TASK] TARGET1 TARGET2 ...\n");
	CommandLine::declare_switch(COPY_TO_CLSW, U"copy-to", 2,
		U"copy target(s) to nest X");
	CommandLine::declare_switch(SYNC_TO_CLSW, U"sync-to", 2,
		U"forcibly copy target(s) to nest X, even if prior version already there");
	CommandLine::declare_boolean_switch(VERSIONS_IN_FILENAMES_CLSW, U"versions-in-filenames", 1,
		U"append _v number to destination filenames on -copy-to or -sync-to", TRUE);
	CommandLine::declare_switch(BUILD_CLSW, U"build", 1,
		U"incrementally build target(s)");
	CommandLine::declare_switch(REBUILD_CLSW, U"rebuild", 1,
		U"completely rebuild target(s)");
	CommandLine::declare_switch(INSPECT_CLSW, U"inspect", 1,
		U"show target(s) but take no action");
	CommandLine::declare_switch(GRAPH_CLSW, U"graph", 1,
		U"show dependency graph of target(s) but take no action");
	CommandLine::declare_switch(USE_NEEDS_CLSW, U"use-needs", 1,
		U"show all the extensions, kits and so on needed to use");
	CommandLine::declare_switch(BUILD_NEEDS_CLSW, U"build-needs", 1,
		U"show all the extensions, kits and so on needed to build");
	CommandLine::declare_switch(USE_LOCATE_CLSW, U"use-locate", 1,
		U"show file paths of all the extensions, kits and so on needed to use");
	CommandLine::declare_switch(BUILD_LOCATE_CLSW, U"build-locate", 1,
		U"show file paths of all the extensions, kits and so on needed to build");
	CommandLine::declare_switch(USE_MISSING_CLSW, U"use-missing", 1,
		U"show the extensions, kits and so on which are needed to use but missing");
	CommandLine::declare_switch(BUILD_MISSING_CLSW, U"build-missing", 1,
		U"show the extensions, kits and so on which are needed to build but missing");
	CommandLine::declare_switch(ARCHIVE_CLSW, U"archive", 1,
		U"sync copies of all extensions, kits and so on needed for -project into Materials");
	CommandLine::declare_switch(ARCHIVE_TO_CLSW, U"archive-to", 2,
		U"sync copies of all extensions, kits and so on needed into nest X");
	CommandLine::declare_switch(TOOLS_CLSW, U"tools", 2,
		U"make X the directory of intools executables");
	CommandLine::declare_boolean_switch(DRY_CLSW, U"dry", 1,
		U"make this a dry run (print but do not execute shell commands)", FALSE);
	CommandLine::declare_boolean_switch(BUILD_TRACE_CLSW, U"build-trace", 1,
		U"show verbose reasoning during -build", FALSE);
	CommandLine::declare_switch(MATCHING_CLSW, U"matching", 2,
		U"apply to all works in nest(s) matching requirement X");
	CommandLine::declare_switch(CONTENTS_OF_CLSW, U"contents-of", 2,
		U"apply to all targets in the directory X");
	CommandLine::declare_boolean_switch(RECURSIVE_CLSW, U"recursive", 1,
		U"run -contents-of recursively to look through subdirectories too", FALSE);
	CommandLine::declare_switch(VERIFY_REGISTRY_CLSW, U"verify-registry", 2,
		U"verify roster.json metadata of registry in the directory X");
	CommandLine::declare_switch(BUILD_REGISTRY_CLSW, U"build-registry", 2,
		U"construct HTML menu pages for registry in the directory X");
	CommandLine::declare_switch(PREPROCESS_HTML_CLSW, U"preprocess-html", 2,
		U"construct HTML page based on X");
	CommandLine::declare_switch(PREPROCESS_HTML_TO_CLSW, U"preprocess-html-to", 2,
		U"set destination for -preprocess-html to be X");
	CommandLine::declare_switch(PREPROCESS_APP_CLSW, U"preprocess-app", 2,
		U"use CSS suitable for app platform X (macos, windows, linux)");
	CommandLine::declare_boolean_switch(REPAIR_CLSW, U"repair", 1,
		U"quietly fix missing or incorrect extension metadata", TRUE);
	CommandLine::declare_switch(RESULTS_CLSW, U"results", 2,
		U"write HTML report file to X (for use within Inform GUI apps)");
	CommandLine::declare_boolean_switch(CONFIRMED_CLSW, U"confirmed", 1,
		U"confirm installation in the Inform GUI apps", TRUE);
	CommandLine::declare_boolean_switch(VERBOSE_CLSW, U"verbose", 1,
		U"equivalent to -verbosity=1", FALSE);
	CommandLine::declare_numerical_switch(VERBOSITY_CLSW, U"verbosity", 1,
		U"how much explanation to print: lowest is 0 (default), highest is 3");
	CommandLine::declare_switch(JSON_CLSW, U"json", 2,
		U"write output of -inspect to a JSON file in X (or '-' for stdout)");
	CommandLine::declare_switch(MODERNISE_CLSW, U"modernise", 1,
		U"update copies to the newest available format");

	CommandLine::begin_group(APP_MANAGEMENT_SUITE_CLSG,
		I"for the use of the Inform GUI apps in managing extensions in materials folders");
	CommandLine::declare_switch(INSTALL_CLSW, U"install", 1,
		U"install extension within the Inform GUI apps");
	CommandLine::declare_switch(UNINSTALL_CLSW, U"uninstall", 1,
		U"remove extension within the Inform GUI apps");
	CommandLine::declare_switch(MODERNISER_CLSW, U"run-moderniser", 1,
		U"like '-modernise' but for use within the Inform GUI apps only");
	CommandLine::end_group();

	CommandLine::begin_group(DOCUMENTATION_SUITE_CLSG,
		I"for generating extension or kit documentation");
	CommandLine::declare_switch(DOCUMENT_CLSW, U"document", 1,
		U"(re-)generate documentation on this within current project");
	CommandLine::declare_switch(DOCUMENT_FROM_CLSW, U"document-from", 2,
		U"generate documentation from documentation in a single Markdown file X");
	CommandLine::declare_switch(DOCUMENT_SET_CLSW, U"document-set", 2,
		U"generate documentation from a full documentation set in the path X");
	CommandLine::declare_switch(DOCUMENT_SITEMAP_CLSW, U"document-sitemap", 2,
		U"use file X as the 'sitemap.txt' when generating documentation sets");
	CommandLine::declare_switch(DOCUMENT_TO_CLSW, U"document-to", 2,
		U"divert generated documentation to directory X");
	CommandLine::end_group();

	CommandLine::begin_group(MARKDOWN_SUITE_CLSG, I"for generating HTML from Markdown");
	CommandLine::declare_switch(MARKDOWN_FROM_CLSW, U"markdown-from", 2,
		U"generate HTML file from Markdown source file X");
	CommandLine::declare_switch(MARKDOWN_TO_CLSW, U"markdown-to", 2,
		U"set filename for single Markdown-generated HTML file to be X");
	CommandLine::declare_switch(MARKDOWN_FROM_DIR_CLSW, U"markdown-from-dir", 2,
		U"generate HTML files from all Markdown sources in X");
	CommandLine::declare_switch(MARKDOWN_TO_DIR_CLSW, U"markdown-to-dir", 2,
		U"generate HTML files from Markdown sources into X");
	CommandLine::declare_switch(MARKDOWN_MODEL_CLSW, U"markdown-model", 2,
		U"use this model file when generating HTML from Markdown ('none' for none)");
	CommandLine::declare_switch(MARKDOWN_VARIATION_CLSW, U"markdown-variation", 2,
		U"use dialect X of Markdown: 'CommonMark', 'GitHub', 'Inform', 'RTP'");
	CommandLine::end_group();

	Supervisor::declare_options();

	CommandLine::read(argc, argv, NULL, &Main::option, &Main::bareword);

	path_to_inbuild = Pathnames::installation_path("INBUILD_PATH", I"inbuild");

@ Here we handle those options not handled by the //supervisor// module.

=
void Main::option(int id, int val, text_stream *arg, void *state) {
	switch (id) {
		case BUILD_CLSW: inbuild_task = BUILD_TTASK; break;
		case REBUILD_CLSW: inbuild_task = REBUILD_TTASK; break;
		case INSPECT_CLSW: inbuild_task = INSPECT_TTASK; break;
		case GRAPH_CLSW: inbuild_task = GRAPH_TTASK; break;
		case USE_NEEDS_CLSW: inbuild_task = USE_NEEDS_TTASK; break;
		case BUILD_NEEDS_CLSW: inbuild_task = BUILD_NEEDS_TTASK; break;
		case USE_LOCATE_CLSW: inbuild_task = USE_LOCATE_TTASK; break;
		case BUILD_LOCATE_CLSW: inbuild_task = BUILD_LOCATE_TTASK; break;
		case DOCUMENT_CLSW: inbuild_task = DOCUMENT_TTASK; break;
		case MODERNISE_CLSW: inbuild_task = MODERNISE_TTASK; break;
		case ARCHIVE_TO_CLSW:
			destination_nest = Nests::new(Pathnames::from_text(arg));
			inbuild_task = ARCHIVE_TO_TTASK;
			break;
		case ARCHIVE_CLSW: inbuild_task = ARCHIVE_TTASK; break;
		case USE_MISSING_CLSW: inbuild_task = USE_MISSING_TTASK; break;
		case BUILD_MISSING_CLSW: inbuild_task = BUILD_MISSING_TTASK; break;
		case TOOLS_CLSW:
			path_to_tools = Pathnames::from_text(arg);
			Supervisor::set_tools_location(path_to_tools); break;
		case MATCHING_CLSW: filter_text = Str::duplicate(arg); break;
		case CONTENTS_OF_CLSW: contents_of_used = TRUE;
			Main::add_directory_contents_targets(Pathnames::from_text(arg)); break;
		case RECURSIVE_CLSW: recursive = val;
			if (contents_of_used) Errors::fatal("-recursive must be used before -contents-of");
			break;
		case DRY_CLSW: dry_run_mode = val; break;
		case BUILD_TRACE_CLSW: build_trace_mode = val; break;
		case COPY_TO_CLSW: inbuild_task = COPY_TO_TTASK;
			destination_nest = Nests::new(Pathnames::from_text(arg));
			break;
		case SYNC_TO_CLSW: inbuild_task = SYNC_TO_TTASK;
			destination_nest = Nests::new(Pathnames::from_text(arg));
			break;
		case VERSIONS_IN_FILENAMES_CLSW:
			Editions::set_canonical_leaves_have_versions(val); break;
		case VERIFY_REGISTRY_CLSW:
		case BUILD_REGISTRY_CLSW:
			selected_registry = Registries::new(Pathnames::from_text(arg));
			if (Registries::read_roster(selected_registry) == FALSE) exit(1);
			if (id == BUILD_REGISTRY_CLSW)
				Registries::build(selected_registry);
			break;
		case PREPROCESS_HTML_TO_CLSW:
			preprocess_HTML_destination = Pathnames::from_text(arg);
			break;
		case PREPROCESS_APP_CLSW:
			preprocess_HTML_app = Str::duplicate(arg);
			break;
		case PREPROCESS_HTML_CLSW:
			if (preprocess_HTML_destination == NULL)
				Errors::fatal("must specify -preprocess-html-to P to give destination path P first");
			filename *F = Filenames::from_text(arg);
			filename *T = Filenames::in(preprocess_HTML_destination, Filenames::get_leafname(F));
			Registries::preprocess_HTML(T, F, preprocess_HTML_app);
			break;
		case REPAIR_CLSW: repair_mode = val; break;
		case INSTALL_CLSW: to_install = Main::file_or_path_to_copy(arg, TRUE); break;
		case UNINSTALL_CLSW: to_uninstall = Main::file_or_path_to_copy(arg, TRUE); break;
		case MODERNISER_CLSW: to_modernise = Main::file_or_path_to_copy(arg, TRUE); break;
		case RESULTS_CLSW: ExtensionInstaller::set_filename(Filenames::from_text(arg)); break;
		case CONFIRMED_CLSW: confirmed = val; break;
		case VERBOSE_CLSW: Supervisor::set_verbosity(1); break;
		case VERBOSITY_CLSW: Supervisor::set_verbosity(val); break;
		case JSON_CLSW:
			JSON_file_format = TRUE;
			if (Str::ne(arg, I"-"))
				JSON_file_to_output = Filenames::from_text(arg);
			break;
		case DOCUMENT_FROM_CLSW: documentation_source = Filenames::from_text(arg); break;
		case DOCUMENT_SET_CLSW: documentation_set = Pathnames::from_text(arg); break;
		case DOCUMENT_SITEMAP_CLSW: documentation_sitemap = Filenames::from_text(arg); break;
		case DOCUMENT_TO_CLSW: documentation_dest = Pathnames::from_text(arg); break;
		
		case MARKDOWN_FROM_CLSW: markdown_settings.from = Filenames::from_text(arg); break;
		case MARKDOWN_TO_CLSW: markdown_settings.to = Filenames::from_text(arg); break;
		case MARKDOWN_FROM_DIR_CLSW: markdown_settings.from_dir = Pathnames::from_text(arg); break;
		case MARKDOWN_TO_DIR_CLSW: markdown_settings.to_dir = Pathnames::from_text(arg); break;
		case MARKDOWN_MODEL_CLSW: markdown_settings.model = Filenames::from_text(arg); break;
		case MARKDOWN_VARIATION_CLSW:
			if (Str::eq_insensitive(arg, I"CommonMark"))
				markdown_settings.variation = MarkdownVariations::CommonMark();
			else if (Str::eq_insensitive(arg, I"GitHub"))
				markdown_settings.variation = MarkdownVariations::GitHub_flavored_Markdown();
			else if (Str::eq_insensitive(arg, I"Inform"))
				markdown_settings.variation = InformFlavouredMarkdown::variation();
			else if (Str::eq_insensitive(arg, I"RTP"))
				markdown_settings.variation = RTPPages::RTP_flavoured_Markdown();
			else Errors::fatal("unrecognised -markdown-variation");
			break;
	}
	Supervisor::option(id, val, arg, state);
}

@ This is called for a command-line argument which doesn't appear as
subordinate to any switch; we take it as the name of a copy.

=
void Main::bareword(int id, text_stream *arg, void *state) {
	Main::add_file_or_path_as_target(arg, TRUE);
}

@h JSON validation.
For options which output JSON, we perform a check that what we've made
conforms to what we say we make.

=
void Main::validate_JSON(JSON_value *obj) {
	filename *F = InstalledFiles::filename(INBUILD_JSON_REQS_IRES);
	dictionary *D = JSON::read_requirements_file(NULL, F);
	JSON_requirement *req = JSON::look_up_requirements(D, I"inbuild-output");
	linked_list *validation_errors = NEW_LINKED_LIST(text_stream);
	if (JSON::validate(obj, req, validation_errors) == FALSE) {
		text_stream *err;
		LOOP_OVER_LINKED_LIST(err, text_stream, validation_errors)
			WRITE_TO(STDERR, "warning: JSON generated did not validate: '%S'", err);
	}
}
