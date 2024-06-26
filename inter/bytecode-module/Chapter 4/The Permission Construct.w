[PermissionInstruction::] The Permission Construct.

Defining the permission construct.

@h Definition.
For what this does and why it is used, see //inter: Textual Inter//.

=
void PermissionInstruction::define_construct(void) {
	inter_construct *IC = InterInstruction::create_construct(PERMISSION_IST, I"permission");
	InterInstruction::specify_syntax(IC,
		I"permission for IDENTIFIER to have IDENTIFIER OPTIONALIDENTIFIER");
	InterInstruction::data_extent_always(IC, 3);
	InterInstruction::permit(IC, INSIDE_PLAIN_PACKAGE_ICUP);
	METHOD_ADD(IC, CONSTRUCT_READ_MTID, PermissionInstruction::read);
	METHOD_ADD(IC, CONSTRUCT_VERIFY_MTID, PermissionInstruction::verify);
	METHOD_ADD(IC, CONSTRUCT_XREF_MTID, PermissionInstruction::xref);
	METHOD_ADD(IC, CONSTRUCT_WRITE_MTID, PermissionInstruction::write);
}

@h Instructions.
In bytecode, the frame of a |permission| instruction is laid out with the
compulsory words -- see //Inter Nodes// -- followed by:

@d PROP_PERM_IFLD    (DATA_IFLD + 0)
@d OWNER_PERM_IFLD   (DATA_IFLD + 1)
@d STORAGE_PERM_IFLD (DATA_IFLD + 2)

=
inter_error_message *PermissionInstruction::new(inter_bookmark *IBM, inter_symbol *prop_s,
	inter_symbol *owner_s, inter_symbol *storage_s, inter_ti level,
	inter_error_location *eloc) {
	inter_ti SID = 0;
	if (storage_s) SID = InterSymbolsTable::id_at_bookmark(IBM, storage_s);
	inter_tree_node *P = Inode::new_with_3_data_fields(IBM, PERMISSION_IST,
		/* PROP_PERM_IFLD: */    InterSymbolsTable::id_at_bookmark(IBM, prop_s),
		/* OWNER_PERM_IFLD: */   InterSymbolsTable::id_at_bookmark(IBM, owner_s),
		/* STORAGE_PERM_IFLD: */ SID,
		eloc, level);
	inter_error_message *E = VerifyingInter::instruction(InterBookmark::package(IBM), P);
	if (E) return E;
	NodePlacement::move_to_moving_bookmark(P, IBM);
	return NULL;
}

@ Verification is quite thorough here: the fields must pass sanity checks, but
then we also require the owner to be the name of an instance or an enumerated
typename, and that its permission list should not already contain a permission
for the same property we are permitting here.

But the process is not entirely passive because we also use verification to add
the new permission to the list for the owner and for the property.

=
void PermissionInstruction::verify(inter_construct *IC, inter_tree_node *P,
	inter_package *owner, inter_error_message **E) {
	*E = VerifyingInter::SID_field(owner, P, PROP_PERM_IFLD, PROPERTY_IST);
	if (*E) return;
	*E = VerifyingInter::POID_field(owner, P, OWNER_PERM_IFLD);
	if (*E) return;
	if (P->W.instruction[STORAGE_PERM_IFLD]) {
		*E = VerifyingInter::SID_field(owner, P, STORAGE_PERM_IFLD, CONSTANT_IST);
		if (*E) return;
	}
}

void PermissionInstruction::xref(inter_construct *IC, inter_tree_node *P,
	inter_error_message **E) {
	inter_symbol *prop_s = InterSymbolsTable::symbol_from_ID_at_node(P, PROP_PERM_IFLD);
	inter_symbol *owner_s = InterSymbolsTable::symbol_from_ID_at_node(P, OWNER_PERM_IFLD);

	inter_node_list *FL = NULL;
	if (TypenameInstruction::is(owner_s)) {
		if (InterTypes::is_enumerated(InterTypes::from_type_name(owner_s)) == FALSE) {
			*E = Inode::error(P, I"property permission for non-enumerated kind", NULL);
			return;
		}
		FL = TypenameInstruction::permissions_list(owner_s);
	} else if (InstanceInstruction::is(owner_s)) {
		FL = InstanceInstruction::permissions_list(owner_s);
	} else {
		*E = Inode::error(P, I"property permission for impossible owner", NULL);
		return;
	}
	if (FL == NULL) {
		*E = Inode::error(P, I"property permission for owner without list", NULL);
		return;
	}
	inter_tree_node *X;
	LOOP_THROUGH_INTER_NODE_LIST(X, FL)
		if (InterSymbolsTable::symbol_from_ID_at_node(X, PROP_PERM_IFLD) == prop_s) {
			*E = Inode::error(P, I"duplicate permission", InterSymbol::identifier(prop_s));
			return;
		}
	InterNodeList::add(FL, P);

	FL = Inode::ID_to_frame_list(P, PropertyInstruction::permissions_list(prop_s));
	if (FL == NULL) {
		*E = Inode::error(P, I"property permission for property without list", NULL);
		return;
	}
	InterNodeList::add(FL, P);
}

@h Creating from textual Inter syntax.

=
void PermissionInstruction::read(inter_construct *IC, inter_bookmark *IBM,
	inter_line_parse *ilp, inter_error_location *eloc, inter_error_message **E) {
	text_stream *owner_name = ilp->mr.exp[0];
	text_stream *prop_name = ilp->mr.exp[1];
	text_stream *storage_name = ilp->mr.exp[2];

	inter_symbol *prop_s =
		TextualInter::find_symbol(IBM, eloc, prop_name, PROPERTY_IST, E);
	if (*E) return;
	inter_symbol *owner_s =
		PropertyValueInstruction::parse_owner(eloc, InterBookmark::scope(IBM), owner_name, E);
	if (*E) return;
	inter_symbol *store = NULL;
	if (Str::len(storage_name) > 0) {
		store = TextualInter::find_symbol(IBM, eloc, storage_name, CONSTANT_IST, E);
		if (*E) return;
	}

	*E = PermissionInstruction::new(IBM, prop_s, owner_s, store,
		(inter_ti) ilp->indent_level, eloc);
}

@h Writing to textual Inter syntax.

=
void PermissionInstruction::write(inter_construct *IC, OUTPUT_STREAM, inter_tree_node *P) {
	WRITE("permission for ");
	TextualInter::write_symbol_from(OUT, P, OWNER_PERM_IFLD);
	WRITE(" to have ");
	TextualInter::write_symbol_from(OUT, P, PROP_PERM_IFLD);
	if (PermissionInstruction::storage(P)) {
		WRITE(" ");
		TextualInter::write_symbol_from(OUT, P, STORAGE_PERM_IFLD);
	}
}

@h Access functions.

=
inter_symbol *PermissionInstruction::property(inter_tree_node *P) {
	if (P == NULL) return NULL;
	if (Inode::isnt(P, PERMISSION_IST)) return NULL;
	return InterSymbolsTable::symbol_from_ID_at_node(P, PROP_PERM_IFLD);
}

inter_symbol *PermissionInstruction::owner(inter_tree_node *P) {
	if (P == NULL) return NULL;
	if (Inode::isnt(P, PERMISSION_IST)) return NULL;
	return InterSymbolsTable::symbol_from_ID_at_node(P, OWNER_PERM_IFLD);
}

inter_symbol *PermissionInstruction::storage(inter_tree_node *P) {
	if (P == NULL) return NULL;
	if (Inode::isnt(P, PERMISSION_IST)) return NULL;
	if (P->W.instruction[STORAGE_PERM_IFLD] == 0) return NULL;
	return InterSymbolsTable::symbol_from_ID_at_node(P, STORAGE_PERM_IFLD);
}
