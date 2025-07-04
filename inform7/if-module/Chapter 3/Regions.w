[Regions::] Regions.

A feature providing support for grouping rooms together into named
and nestable regions.

@ "Region" is in fact one of the four top-level kinds in the standard I7
world model, alongside thing, room and direction. What makes it complicated
is that it can contain rooms and other regions, but that this form of
containment is implemented differently from spatial containment: as a
result, a new "regional containment" relation is needed.

=
void Regions::start(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-function-pointer-types-strict"
	PluginCalls::plug(CREATE_INFERENCE_SUBJECTS_PLUG, Regions::create_inference_subjects);
	PluginCalls::plug(NEW_BASE_KIND_NOTIFY_PLUG, Regions::new_base_kind_notify);
	PluginCalls::plug(SET_SUBKIND_NOTIFY_PLUG, Regions::set_subkind_notify);
	PluginCalls::plug(NEW_SUBJECT_NOTIFY_PLUG, Regions::new_subject_notify);
	PluginCalls::plug(NEW_PROPERTY_NOTIFY_PLUG, Regions::new_property_notify);
	PluginCalls::plug(COMPLETE_MODEL_PLUG, Regions::complete_model);
	PluginCalls::plug(MORE_SPECIFIC_PLUG, Regions::more_specific);
	PluginCalls::plug(INTERVENE_IN_ASSERTION_PLUG, Regions::intervene_in_assertion);
	PluginCalls::plug(NAME_TO_EARLY_INFS_PLUG, Regions::name_to_early_infs);
#pragma clang diagnostic pop
}

@ There is one kind of interest: "region", of course. It is recognised by the English
name in the Standard Rules. (So there is no need to translate this to other languages.)

= (early code)
kind *K_region = NULL;
inference_subject *infs_region = NULL;

@ =
<notable-regions-kinds> ::=
	region

@ =
int Regions::new_base_kind_notify(kind *new_base, char *text_stream, wording W) {
	if (<notable-regions-kinds>(W)) {
		K_region = new_base; return TRUE;
	}
	return FALSE;
}

@ As with the handling of the main spatial kinds, we need a placeholder for the
"region" subject until |K_region| is ready to be created.

=
int Regions::create_inference_subjects(void) {
	infs_region = InferenceSubjects::new_fundamental(global_constants, "region(early)");
	return FALSE;
}
int Regions::name_to_early_infs(wording W, inference_subject **infs) {
	if ((<notable-regions-kinds>(W)) && (K_region == NULL)) *infs = infs_region;
	return FALSE;
}

@ Region is not allowed to be made a subkind of anything else:

=
int Regions::set_subkind_notify(kind *sub, kind *super) {
	if ((sub == K_region) && (super != K_object)) {
		if (problem_count == 0)
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_RegionAdrift),
				"'region' is not allowed to be a kind of anything (other than "
				"'object')",
				"because it's too fundamental to the way Inform maps out the "
				"geography of the physical world.");
		return TRUE;
	}
	return FALSE;
}

@ Note that because we use regular |parentage_inf| inferences to remember
that one region is inside another, it follows that the progenitor of a
region is either the next broadest region containing it, or else |NULL|.

=
instance *Regions::enclosing(instance *reg) {
	instance *P = NULL;
	if (Spatial::object_is_a_room(reg)) P = REGIONS_DATA(reg)->in_region;
	if (Regions::object_is_a_region(reg)) P = Spatial::progenitor(reg);
	if (Regions::object_is_a_region(P) == FALSE) return NULL;
	return P;
}

@ Rooms are always more specific than regions; if region X is within
region Y, then X is more specific than Y; otherwise any two regions are
equally specific. (This is used in sorting rules by the specificity of their
domains.)

=
int Regions::more_specific(instance *I1, instance *I2) {
	int r1 = Instances::of_kind(I1, K_room);
	int r2 = Instances::of_kind(I2, K_room);
	int reg1 = Instances::of_kind(I1, K_region);
	int reg2 = Instances::of_kind(I2, K_region);
	if ((r1) && (reg2)) return 1;
	if ((reg1) && (r2)) return -1;
	if ((reg1) && (reg2)) {
		if (Spatial::encloses(I1, I2)) return 1;
		if (Spatial::encloses(I2, I1)) return -1;
	}
	return 0;
}

@ Detecting regions is easy. Note that if this feature is inactive then
|K_region| will be null, and this will always return false.

=
int Regions::object_is_a_region(instance *I) {
	if ((K_region) && (I) && (Instances::of_kind(I, K_region))) return TRUE;
	return FALSE;
}

@ Every inference subject contains a pointer to its own unique copy of the
following minimal structure, though it will only be relevant for instances of
"region":

@d REGIONS_DATA(I) FEATURE_DATA_ON_INSTANCE(regions, I)

=
typedef struct regions_data {
	struct instance *in_region; /* smallest region containing me (rooms only) */
	struct parse_node *in_region_set_at; /* where this is decided */
	struct inter_name *in_region_iname; /* for testing regional containment found-ins */
	CLASS_DEFINITION
} regions_data;

int Regions::new_subject_notify(inference_subject *subj) {
	regions_data *rd = CREATE(regions_data);
	rd->in_region = NULL;
	rd->in_region_set_at = NULL;
	rd->in_region_iname = NULL;
	ATTACH_FEATURE_DATA_TO_SUBJECT(regions, subj, rd);
	return FALSE;
}

@ =
parse_node *Regions::in_region_set_at(instance *I) {
	if (I == NULL) return NULL;
	if (FEATURE_INACTIVE(regions)) return NULL;
	return REGIONS_DATA(I)->in_region_set_at;
}

@ This is a property name to do with regions which Inform provides special
support for; it recognises the English name when it is defined by the
Standard Rules. (So there is no need to translate this to other languages.)

=
<notable-regions-properties> ::=
	map region

@ =
property *P_map_region = NULL; /* a value property giving the region of a room */
int Regions::new_property_notify(property *prn) {
	if (<notable-regions-properties>(prn->name))
		P_map_region = prn;
	return FALSE;
}

@ The following doesn't really intervene at all: it simply produces two problem
messages which would have been less helpful if core Inform had produced them.

=
int Regions::intervene_in_assertion(parse_node *px, parse_node *py) {
	if ((Node::get_type(px) == PROPER_NOUN_NT) &&
		(Node::get_type(py) == COMMON_NOUN_NT)) {
		inference_subject *left_subject = Node::get_subject(px);
		inference_subject *right_kind = Node::get_subject(py);
		if ((InferenceSubjects::is_an_object(left_subject)) &&
			(right_kind == KindSubjects::from_kind(K_region))) {
			instance *left_object = InstanceSubjects::to_object_instance(left_subject);
			if ((left_object) &&
				(current_sentence != Instances::get_creating_sentence(left_object)) &&
				(Instances::of_kind(left_object, K_region) == FALSE)) {
				StandardProblems::subject_problem_at_sentence(_p_(PM_ExistingRegion),
					left_subject,
					"(which I notice in another sentence) seems now to "
					"be declared as a new region",
					"which is suspect. Perhaps I have misinterpreted what was "
					"meant to be a new name for an old one?");
				return TRUE;
			}
		}
	}
	if ((Node::get_type(px) == RELATIONSHIP_NT) &&
		(Node::get_subject(py) == KindSubjects::from_kind(K_region))) {
		UsingProblems::assertion_problem(Task::syntax_tree(), _p_(PM_RegionRelated),
			"a region cannot be given a specific location",
			"since it contains what may be many rooms, which may not be "
			"contiguous and could be scattered about all over. (Sometimes "
			"this problem arises because an ambiguous sentence like 'East "
			"of Eden is a region.' has been used: Inform reads that as "
			"saying that a nameless region lies to the east of the room "
			"'Eden'. The desired effect can be got using 'called' to stop "
			"Inform taking 'East of' literally: for instance, 'The Land of "
			"Nod is in a region called East of Eden.'");
		return TRUE;
	}
	return FALSE;
}

@ Model completion:

=
int Regions::complete_model(int stage) {
	if (stage == WORLD_STAGE_II) @<Assert map-region properties of rooms and regions@>;
	if (stage == WORLD_STAGE_III) @<Assert regional-found-in properties of regions@>;
	return FALSE;
}

@ The following is needed in case somebody does something like this:

>> A desert room is a kind of room. The map region of a desert room is usually Sahara.

@<Assert map-region properties of rooms and regions@> =
	instance *I;
	LOOP_OVER_INSTANCES(I, K_object)
		if ((Instances::of_kind(I, K_room)) ||
			(Instances::of_kind(I, K_region))) {
			parse_node *where = NULL;
			parse_node *val = PropertyInferences::value_and_where(
				Instances::as_subject(I), P_map_region, &where);
			if (val) {
				instance *reg =
					Rvalues::to_object_instance(val);
				REGIONS_DATA(I)->in_region = reg;
				REGIONS_DATA(I)->in_region_set_at = where;
			}
		}

@<Assert regional-found-in properties of regions@> =
	property *P_regional_found_in = ValueProperties::new_nameless(
		I"regional_found_in", K_text);
	instance *I;
	LOOP_OVER_INSTANCES(I, K_object)
		if (Instances::of_kind(I, K_region)) {
			inter_name *iname = RTRegionInstances::found_in_iname(I);
			ValueProperties::assert(P_regional_found_in, Instances::as_subject(I),
				Rvalues::from_iname(iname), CERTAIN_CE);
		}

@ The relation "R in S" behaves so differently for regions that we need to
define it separately, even though there's no difference in English syntax. So:

= (early code)
binary_predicate *R_regional_containment = NULL;

@ =
void Regions::create_relations(void) {
	R_regional_containment =
		BinaryPredicates::make_pair(spatial_bp_family,
			BPTerms::new(infs_region),
			BPTerms::new(KindSubjects::from_kind(K_object)),
			I"region-contains", I"in-region",
			Calculus::Schemas::new("SetRegionalContainment(*2,*1)"),
			Calculus::Schemas::new("TestRegionalContainment(*2,*1)"),
			PreformUtilities::wording(<relation-names>,
				REGIONAL_CONTAINMENT_RELATION_NAME));
	BinaryPredicates::set_index_details(R_regional_containment, NULL, "room/region");
}

@ We intervene only in limited cases: X contains Y, X regionally contains Y,
or X incorporates Y; and only when X is a region. (This of course only
applies to the built-in spatial relationships; regions are entirely free
to participate in nonspatial relations.)

=
int Regions::assert_relations(binary_predicate *relation,
	instance *I0, instance *I1) {
	int I0_is_region = FALSE;
	if (Instances::of_kind(I0, K_region)) I0_is_region = TRUE;
	int I1_is_region = FALSE;
	if (Instances::of_kind(I1, K_region)) I1_is_region = TRUE;

	if (I0_is_region) {
		if ((relation == R_incorporation) ||
			(relation == R_containment) ||
			(relation == R_regional_containment)) {
			@<You can only be declared as in one region@>;
			if (I1_is_region) @<A region is being put inside a region@>
			else @<A room is being put inside a region@>;
		} else {
			StandardProblems::sentence_problem(Task::syntax_tree(),
				_p_(PM_RegionRelation),
				"regions can only contain rooms",
				"and have no other relationships.");
		}
		return TRUE;
	} else if (I1_is_region) {
		if ((relation == R_incorporation) ||
			(relation == R_containment) ||
			(relation == R_regional_containment)) {
			StandardProblems::sentence_problem(Task::syntax_tree(),
				_p_(PM_RegionRelation2),
				"regions can only be contained in other regions",
				"and not for example in rooms.");
		}
	}

	return FALSE;
}

@<You can only be declared as in one region@> =
	if ((REGIONS_DATA(I1)->in_region) &&
		(REGIONS_DATA(I1)->in_region != I0)) {
		StandardProblems::sentence_problem(Task::syntax_tree(),
			_p_(PM_RegionInTwoRegions),
			"each region can only be declared to be inside a single "
			"other region",
			"since although regions can be placed inside each other, "
			"they are not permitted to overlap.");
		return TRUE;
	}
	REGIONS_DATA(I1)->in_region = I0;
	REGIONS_DATA(I1)->in_region_set_at = current_sentence;

@<A region is being put inside a region@> =
	inference_subject *inner = Instances::as_subject(I1);
	inference_subject *outer = Instances::as_subject(I0);
	SpatialInferences::infer_parentage(inner, CERTAIN_CE, outer);

@ Anything in or part of a region is necessarily a room, if it isn't known
to be a region already:

@<A room is being put inside a region@> =
	inference_subject *rm = Instances::as_subject(I1);
	parse_node *spec = Rvalues::from_instance(I0);
	Propositions::Abstract::assert_kind_of_instance(I1, K_room);
	PropertyInferences::draw(rm, P_map_region, spec);

