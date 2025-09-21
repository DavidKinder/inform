[Coverage::] Problem Coverage.

To see which problem messages have test cases and which are linked
to the documentation.

@h Observation.
Problem messages are identified by their code-names, e.g., |PM_MisplacedFrom|;
those names should be unique, but any number of problems can instead be
marked with one of three special names.

Problems can be mentioned in the code, in the documentation, or in the
set of Inform test cases.

@d CASE_EXISTS_PCON    0x00000001 /* mentioned in test cases */
@d DOC_MENTIONS_PCON   0x00000002 /* mentioned in documentation */
@d CODE_MENTIONS_PCON  0x00000004 /* mentioned in source code */
@d IMPOSSIBLE_PCON     0x00000008 /* this is |BelievedImpossible| */
@d UNTESTABLE_PCON     0x00000010 /* this is |Untestable| */
@d NAMELESS_PCON       0x00000020 /* this is |...| */

=
typedef struct known_problem {
	struct text_stream *name;
	int contexts_observed; /* bitmap of the above bits */
	int contexts_observed_multiple_times; /* bitmap of the above bits */
	CLASS_DEFINITION
} known_problem;

@ When a problem is observed, we create a dictionary entry for it, if necessary,
and augment its bitmap of known contexts:

=
dictionary *problems_dictionary = NULL;

void Coverage::observe_problem(text_stream *name, int context) {
	if (problems_dictionary == NULL)
		problems_dictionary = Dictionaries::new(1000, FALSE);
	known_problem *KP = NULL;
	if (Dictionaries::find(problems_dictionary, name)) {
		KP = (known_problem *) Dictionaries::read_value(problems_dictionary, name);
	} else {
		KP = CREATE(known_problem);
		Dictionaries::create(problems_dictionary, name);
		Dictionaries::write_value(problems_dictionary, name, (void *) KP);
		KP->name = Str::duplicate(name);
		KP->contexts_observed = 0;
		KP->contexts_observed_multiple_times = 0;
	}
	if (KP->contexts_observed & context)
		KP->contexts_observed_multiple_times |= context;
	KP->contexts_observed |= context;
}

@h Problems which have test cases.
Here we ask Intest to produce a roster of all known test cases, then parse
this back to look for cases whose names have the |PM_...| format. Those are
the problem message test cases, so we observe them.

=
void Coverage::which_problems_have_test_cases(void) {
	filename *CAT = Filenames::in(path_to_inpolicy_workspace, I"cases.txt");
	TEMPORARY_TEXT(COMMAND)
	WRITE_TO(COMMAND, "..%cintest%cTangled%cintest inform7 -catalogue ",
		FOLDER_SEPARATOR, FOLDER_SEPARATOR, FOLDER_SEPARATOR);
	Shell::redirect(COMMAND, CAT);
	if (Shell::run(COMMAND)) Errors::fatal("can't run intest to harvest cases");
	DISCARD_TEXT(COMMAND)
	TextFiles::read(CAT, FALSE, "unable to read roster of test cases", TRUE,
		&Coverage::test_case_harvester, NULL, NULL);
}

void Coverage::test_case_harvester(text_stream *text, text_file_position *tfp, void *state) {
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, text, U"(PM_%C+)%c*"))
		Coverage::observe_problem(mr.exp[0], CASE_EXISTS_PCON);
	Regexp::dispose_of(&mr);
}

@h Problems mentioned in documentation.
Here we look through the "Writing with Inform" source text for cross-references
to problem messages:

=
void Coverage::which_problems_are_referenced(void) {
	pathname *D = Pathnames::from_text(I"resources");
	D = Pathnames::down(D, I"Documentation");
	filename *WWI = Filenames::in(D, I"Writing with Inform.md");
	TextFiles::read(WWI, FALSE, "unable to read 'Writing with Inform' source text", TRUE,
		&Coverage::xref_harvester, NULL, NULL);
}

void Coverage::xref_harvester(text_stream *text, text_file_position *tfp, void *state) {
	match_results mr = Regexp::create_mr();
	while (Regexp::match(&mr, text, U"(%c*)%{(PM_%C+?)%}(%c*)")) {
		Coverage::observe_problem(mr.exp[1], DOC_MENTIONS_PCON);
		Str::clear(text);
		WRITE_TO(text, "%S%S", mr.exp[0], mr.exp[2]);
	}
	Regexp::dispose_of(&mr);
}

@h Problems generated in the I7 source.
Which is to say, actually existing problem messages.

=
void Coverage::which_problems_exist(void) {
	pathname *tools = Pathnames::up(path_to_inpolicy);
	pathname *path_to_inform7 = Pathnames::down(tools, I"inform7");
	wcl_declaration *D = WCL::read_web(path_to_inform7, NULL);
	if (D) {
		ls_web *Wm = WebStructure::from_declaration(D);
		ls_chapter *Cm;
		LOOP_OVER_LINKED_LIST(Cm, ls_chapter, Wm->chapters) {
			ls_section *Sm;
			LOOP_OVER_LINKED_LIST(Sm, ls_section, Cm->sections) {
				filename *SF = Sm->source_file_for_section;
				TextFiles::read(SF, FALSE, "unable to read section page from 'inform7'",
					TRUE, &Coverage::existence_harvester, NULL, (void *) SF);
			}
		}
	}
}

@ So now we have to read a section, looking for the existence of problem
messages:

=
void Coverage::existence_harvester(text_stream *text, text_file_position *tfp, void *state) {
	filename *SF = (filename *) state;
	match_results mr = Regexp::create_mr();
	while (Regexp::match(&mr, text, U"(%c*?)_p_%((%c+?)%)(%c*)")) {
		Str::clear(text);
		WRITE_TO(text, "%S%S", mr.exp[0], mr.exp[2]);
		TEMPORARY_TEXT(name)
		Str::copy(name, mr.exp[1]);
		if (Str::eq(name, I"sigil")) break;
		int context = CODE_MENTIONS_PCON;
		if (Str::eq(name, I"BelievedImpossible")) {
			context = IMPOSSIBLE_PCON;
			WRITE_TO(name, "_%f_line%d", SF, tfp->line_count);
		} else if (Str::eq(name, I"Untestable")) {
			context = UNTESTABLE_PCON;
			WRITE_TO(name, "_%f_line%d", SF, tfp->line_count);
		} else if (Str::eq(name, I"...")) {
			context = NAMELESS_PCON;
			WRITE_TO(name, "_%f_line%d", SF, tfp->line_count);
		}
		Coverage::observe_problem(name, context);
		DISCARD_TEXT(name)
	}
	Regexp::dispose_of(&mr);
}

@h Checking.
So the actual policy-enforcement routine is here:

=
int observations_made = FALSE;
int Coverage::check(OUTPUT_STREAM) {
	if (observations_made == FALSE) {
		@<Perform the observations@>;
		observations_made = TRUE;
	}

	int all_is_well = TRUE;
	@<Report and decide how grave the situation is@>;
	if (all_is_well) WRITE("All is well.\n");
	else WRITE("This needs attention.\n");
	WRITE("\n");
	return all_is_well;
}

@<Perform the observations@> =
	Coverage::which_problems_have_test_cases();
	Coverage::which_problems_are_referenced();
	Coverage::which_problems_exist();

@ Okay, so that's all of the scanning done; now to report on it.

@<Report and decide how grave the situation is@> =
	WRITE("%d problem name(s) have been observed:\n", NUMBER_CREATED(known_problem)); INDENT;

	WRITE("Problems actually existing (the source code refers to them):\n"); INDENT;
	Coverage::cite(OUT, CODE_MENTIONS_PCON, 0, CODE_MENTIONS_PCON,
		I"are named and in principle testable");
	if (Coverage::cite(OUT, 0, CODE_MENTIONS_PCON, CODE_MENTIONS_PCON,
		I"are named more than once:") > 0) {
		all_is_well = FALSE;
		Coverage::list(OUT, 0, CODE_MENTIONS_PCON, CODE_MENTIONS_PCON);
	}
	Coverage::cite(OUT, IMPOSSIBLE_PCON, 0, IMPOSSIBLE_PCON,
		I"are 'BelievedImpossible', that is, no known source text causes them");
	Coverage::cite(OUT, UNTESTABLE_PCON, 0, UNTESTABLE_PCON,
		I"are 'Untestable', that is, not mechanically testable");
	Coverage::cite(OUT, NAMELESS_PCON, 0, NAMELESS_PCON,
		I"are '...', that is, they need to be give a name and a test case");
	OUTDENT;

	WRITE("Problems which should have test cases:\n"); INDENT;
	Coverage::cite(OUT, CASE_EXISTS_PCON+CODE_MENTIONS_PCON, 0, CASE_EXISTS_PCON+CODE_MENTIONS_PCON,
		I"have test cases");
	if (Coverage::cite(OUT, CASE_EXISTS_PCON+CODE_MENTIONS_PCON, 0, CODE_MENTIONS_PCON,
		I"have no test case yet:") > 0) {
		Coverage::list(OUT, CASE_EXISTS_PCON+CODE_MENTIONS_PCON, 0, CODE_MENTIONS_PCON);
	}
	if (Coverage::cite(OUT, CASE_EXISTS_PCON+CODE_MENTIONS_PCON, 0, CASE_EXISTS_PCON,
		I"are spurious test cases, since no such problems exist:") > 0) {
		all_is_well = FALSE;
		Coverage::list(OUT, CASE_EXISTS_PCON+CODE_MENTIONS_PCON, 0, CASE_EXISTS_PCON);
	}
	OUTDENT;

	WRITE("Problems which are cross-referenced in 'Writing with Inform':\n"); INDENT;
	Coverage::cite(OUT, CODE_MENTIONS_PCON+DOC_MENTIONS_PCON, 0, CODE_MENTIONS_PCON+DOC_MENTIONS_PCON,
		I"are cross-referenced");
	if (Coverage::cite(OUT, 0, DOC_MENTIONS_PCON, DOC_MENTIONS_PCON,
		I"are cross-referenced more than once:") > 0) {
		all_is_well = FALSE;
		Coverage::list(OUT, 0, DOC_MENTIONS_PCON, DOC_MENTIONS_PCON);
	}
	if (Coverage::cite(OUT, CODE_MENTIONS_PCON+DOC_MENTIONS_PCON, 0, DOC_MENTIONS_PCON,
		I"are spurious references, since no such problems exist:") > 0) {
		all_is_well = FALSE;
		Coverage::list(OUT, CODE_MENTIONS_PCON+DOC_MENTIONS_PCON, 0, DOC_MENTIONS_PCON);
	}
	OUTDENT;
	OUTDENT;

@ =
int Coverage::cite(OUTPUT_STREAM, int mask, int mask2, int val, text_stream *message) {
	int N = 0;
	known_problem *KP;
	LOOP_OVER(KP, known_problem) {
		if ((KP->contexts_observed & mask) == val) N++;
		if ((KP->contexts_observed_multiple_times & mask2) == val) N++;
	}
	if ((N>0) && (message)) WRITE("%d problem(s) %S\n", N, message);
	return N;
}

void Coverage::list(OUTPUT_STREAM, int mask, int mask2, int val) {
	INDENT;
	known_problem *KP;
	LOOP_OVER(KP, known_problem)
		if (((KP->contexts_observed & mask) == val) ||
			((KP->contexts_observed_multiple_times & mask2) == val)) {
			WRITE("%S\n", KP->name);
		}
	OUTDENT;
}
