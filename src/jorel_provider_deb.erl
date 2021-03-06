% @hidden
-module(jorel_provider_deb).
-behaviour(jorel_provider).
-include("../include/jorel.hrl").

-export([init/1, do/1]).
-define(PROVIDER, deb).

init(State) ->
  jorel_config:add_provider(
    State,
    {?PROVIDER,
     #{
       module => ?MODULE,
       depends => [release],
       desc => "Create a Debian package"
      }
    }
   ).

do(State) ->
  ?INFO("== Start provider ~p", [?PROVIDER]),
  {output_dir, Outdir} = jorel_config:get(State, output_dir),
  {relname, RelName} = jorel_config:get(State, relname),
  {relvsn, RelVsn} = jorel_config:get(State, relvsn),
  {include_erts, IncludeErts} = jorel_config:get(State, include_erts, true),
  R = filename:join([Outdir, RelName, "releases", RelVsn, "RELEASES"]),
  Erts = case file:consult(R) of
           {ok, [[{release,
                   _,
                   _,
                   ErtsVersion,
                   _,
                   permanent}]]} -> ErtsVersion;
           _ ->
             undefined
         end,
  FileMap = [
             {"debian/changelog", deb_debian_changelog_dtl},
             {"debian/compat", deb_debian_compat_dtl},
             {"debian/control", deb_debian_control_dtl},
             {"debian/copyright", deb_debian_copyright_dtl},
             {"debian/postinst", deb_debian_postinst_dtl},
             {"debian/postrm", deb_debian_postrm_dtl},
             {"debian/rules", deb_debian_rules_dtl},
             {"debian/" ++ eutils:to_string(RelName) ++ ".init", deb_debian_init_dtl},
             {"debian/" ++ eutils:to_string(RelName) ++ ".install", deb_debian_install_dtl}
            ],
  {deb, DebData} = jorel_config:get(State, deb, []),
  DebData1 = DebData ++
    [{pkgname, RelName},
     {relname, RelName},
     {relvsn, RelVsn}] ++
    case {IncludeErts, Erts} of
      {true, Erts} when Erts =/= undefined -> [{erts_version, Erts}];
      _ -> []
    end,
  eos:in(filename:join([Outdir, RelName]), fun() ->
                        case efile:make_dir("debian") of
                          ok ->
                            lists:foreach(fun({File, Template}) ->
                                              ?INFO("* Create file ~s", [File]),
                                              {ok, Content} = Template:render(DebData1),
                                              ok = file:write_file(File, iolist_to_binary(Content))
                                          end, FileMap),
                            ?INFO("* Build package.", []),
                            _Output = os:cmd("debuild --no-tgz-check -i -us -uc -b");
                            % ?INFO("~s", [unicode:characters_to_binary(Output)]);
                          {error, Reason} ->
                            ?HALT("!!! Failed ro create ~s: ~p", [filename:join([Outdir, "debian"]), Reason])
                        end
                    end),
  ?INFO("== Provider ~p complete", [?PROVIDER]),
  State.

