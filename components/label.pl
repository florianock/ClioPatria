/*  Part of ClioPatria SeRQL and SPARQL server

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2010, University of Amsterdam,
		   VU University Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(cp_label,
	  [ turtle_label//1,		% +Literal
	    rdf_link//1,		% +RDFTerm
	    rdf_link//2			% +RDFTerm, +Options
	  ]).
:- use_module(library(error)).
:- use_module(library(option)).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).
:- use_module(library(aggregate)).
:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdf_label)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_dispatch)).

:- use_module(cliopatria(hooks)).

/** <module> Support for showing labels

This module provides HTML components to display labels for resources.

@see	library(semweb/rdf_label) returns textual labels.
*/


%%	turtle_label(+RDFTerm)// is det.
%
%	HTML  rule  to  emit  an  RDF   term  (resource  or  object)  in
%	turtle-like notation with CSS classes.
%
%	@tbd	Implement possibility for a summary.

turtle_label(R) -->
	{ atom(R),
	  rdf_global_id(NS:Local, R), !
	},
	html(['<', span(class(prefix), NS), ':', span(class(local), Local), '>']).
turtle_label(R) -->
	{ atom(R),
	  label_property(P),
	  rdf_has(R, P, Value),
	  literal_text(Value, Label), !
	},
	html(Label).
turtle_label(R) -->
	{ rdf_is_bnode(R) },
	bnode_label(R), !.
turtle_label(R) -->
	{ atom(R) }, !,
	html(R).
turtle_label(literal(Lit)) --> !,
	literal_label(Lit).


literal_label(type(Type, Value)) --> !,
	html(span(class(literal),
		  ['"', span(class(l_text), Value),
		   '"', span(class(l_type), '^^'), \turtle_label(Type)])).
literal_label(lang(Lang, Value)) --> !,
	html(span(class(literal),
		  ['"', span(class(l_text), Value), '"',
		   span(class(l_lang), '@'), span(class(lang), Lang)])).
literal_label(Value) -->
	html(span(class(literal),
		  ['"', span(class(l_text), Value), '"'])).


%%	bnode_label(+Resource)// is semidet.
%
%	Display an HTML label for an  RDF   blank  node.  This DCG rules
%	first  calls  the  hook  cliopatria:bnode_label//1.  On  failure
%	performs its default task:
%
%	    * If the bnode has an rdf:value, display the label thereof
%	    with [<label>...]
%
%	    * If the bnode is an RDF collection, display its first 5
%	    members as (<member-1>, <member-2, ...)

bnode_label(R) -->
	cliopatria:bnode_label(R), !.
bnode_label(R) -->
	{ rdf(R, rdf:value, Value),
	  (   Value = literal(_)
	  ;   \+ rdf_is_bnode(Value)
	  )
	}, !,
	html(span([ class(rdf_bnode),
		    title('RDF bnode using rdf:value')
		  ],
		  ['[', \turtle_label(Value), '...]'])).
bnode_label(R) -->
	{ rdf_collection_list(R, List), !,
	  length(List, Len),
	  format(string(Title), 'RDF collection with ~D members', Len)
	},
	html(span([ class(rdf_list),
		    title(Title)
		  ],
		  ['(', \collection_members(List, 0, Len, 5), ')'])).

collection_members([], _, _, _) --> [].
collection_members(_, Max, Total, Max) --> !,
	{ Left is Total - Max },
	html('... ~D more'-[Left]).
collection_members([H|T], I, Total, Max) -->
	turtle_label(H),
	(   { T == [] }
	->  []
	;   html(','),
	    { I2 is I + 1 },
	    collection_members(T, I2, Total, Max)
	).


rdf_collection_list(R, []) :-
	rdf_equal(rdf:nil, R), !.
rdf_collection_list(R, [H|T]) :-
	rdf_has(R, rdf:first, H),
	rdf_has(R, rdf:rest, RT),
	rdf_collection_list(RT, T).


%%	rdf_link(+URI)// is det.
%%	rdf_link(+URI, +Options)// is det.
%
%	Make a hyper-link to an arbitrary   RDF resource or object using
%	the label.  Options processed:
%
%	    * resource_format(+Format)
%	    Determines peference for displaying resources.  Values are:
%
%	        * plain
%	        Display full resource a plain text
%	        * label
%	        Try to display a resource using its label
%	        * nslabel
%	        Try to display a resource as <prefix>:<Label>
%
%	This predicate creates two types of  links. Resources are linked
%	to the handler implementing   =list_resource= using r=<resource>
%	and  literals  that  appear  multiple    times   are  linked  to
%	=list_triples_with_object= using a Prolog  representation of the
%	literal.
%
%	This predicate can be hooked using cliopatria:display_link//2.
%
%	@tbd	Make it easier to determine the format of the label
%	@tbd	Allow linking to different handlers.

rdf_link(R) -->
	rdf_link(R, []).

rdf_link(R, Options) -->
	cliopatria:display_link(R, Options), !.
rdf_link(R, Options) -->
	{ atom(R), !,
	  resource_link(R, Options, HREF),
	  (   rdf(R, _, _)
	  ->  Class = r_def
	  ;   rdf_graph(R)
	  ->  Class = r_graph
	  ;   Class = r_undef
	  )
	},
	html(a([class(Class), href(HREF)], \resource_label(R, Options))).
rdf_link(Literal, Options) -->
	{ (   option(graph(Graph), Options)
	  ->  aggregate_all(count, rdf(_,_,Literal, Graph), Count)
	  ;   aggregate_all(count, rdf(_,_,Literal), Count)
	  ),
	  Count > 1, !,
	  format(string(Title), 'Used ~D times', [Count]),
	  term_to_atom(Literal, Atom),
	  http_link_to_id(list_triples_with_object, [l=Atom], HREF)
	},
	html(a([ class(l_count),
		 href(HREF),
		 title(Title)
	       ],
	       \turtle_label(Literal))).
rdf_link(Literal, _) -->
	turtle_label(Literal).

resource_link(_, Options, HREF) :-
	option(link(To), Options), !,
	To =.. [ID|Parms],
	http_link_to_id(ID, Parms, HREF).
resource_link(R, _, HREF) :-
	http_link_to_id(list_resource, [r=R], HREF).


resource_label(R, Options) -->
	{ option(resource_format(Format), Options) }, !,
	resource_flabel(Format, R).
resource_label(R, _) -->
	turtle_label(R).

resource_flabel(plain, R) --> !,
	html(R).
resource_flabel(label, R) --> !,
	(   { rdf_display_label(R, Label) }
	->  html([span(class(r_label),Label)])
	;   turtle_label(R)
	).
resource_flabel(nslabel, R) --> !,
	(   { rdf_global_id(NS:_Local, R), !,
	      rdf_display_label(R, Label)
	    }
	->  html([span(class(prefix),NS),':',span(class(r_label),Label)])
	;   turtle_label(R)
	).
resource_flabel(_, R) -->
	turtle_label(R).
