# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ResourcesTest do
  @moduledoc """
  The resources primitive: `resources/list`, `resources/templates/list`, `resources/read`,
  the `resources` capability, and the one-reader rule that keeps what is advertised and what
  is readable from drifting apart. The method set is the 2026-07-28 schema's, derived and
  recorded before this file was written; each method answered `-32601` on the tree it was
  added to.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.{Catalog, Cursor, ResourceSpec, ResourceTemplateSpec, Server}

  @modern %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }
  @legacy %{"io.modelcontextprotocol/protocolVersion" => "2025-11-25"}

  # A catalog whose entries exist in NO other catalog of this suite, so that a test asserting
  # they are honoured cannot pass by coincidence -- the defect that produced this package's
  # first commit was a fake whose entries happened to exist in the real catalog too.
  defmodule Injected do
    @behaviour Catalog

    @impl true
    def capabilities do
      %{
        tools: [],
        resources: [
          %ResourceSpec{uri: "injected://only-here/z", name: "z"},
          %ResourceSpec{
            uri: "injected://only-here/a",
            name: "a",
            title: "A",
            description: "the first",
            mime_type: "text/plain",
            size: 3
          },
          %ResourceSpec{uri: "injected://only-here/m", name: "m"},
          %ResourceTemplateSpec{
            uri_template: "injected://only-here/by-id/{id}",
            name: "by-id",
            mime_type: "application/json"
          },
          %ResourceTemplateSpec{uri_template: "injected://only-here/tree/{+path}", name: "tree"},
          %ResourceTemplateSpec{uri_template: "injected://only-here/{name}.txt", name: "dotted"}
        ],
        prompts: []
      }
    end

    @impl true
    def read_resource("injected://only-here/a"),
      do: {:ok, [%{uri: "injected://only-here/a", text: "abc", mime_type: "text/plain"}]}

    def read_resource("injected://only-here/m"),
      do: {:ok, [%{uri: "injected://only-here/m", blob: <<0, 255, 1>>}]}

    def read_resource("injected://only-here/z"), do: {:error, "z is gone"}

    def read_resource("injected://only-here/by-id/" <> id),
      do: {:ok, [%{uri: "injected://only-here/by-id/#{id}", text: ~s({"id":"#{id}"})}]}

    def read_resource("injected://only-here/tree/" <> path),
      do: {:ok, [%{uri: "injected://only-here/tree/#{path}", text: path}]}

    def read_resource("injected://only-here/" <> file),
      do: {:ok, [%{uri: "injected://only-here/#{file}", text: file}]}

    # Host code must never run for a uri the catalog does not list or match: the refusal is
    # the server's, before this function. A raise here is how a test tells the two apart.
    def read_resource(other), do: raise("host code ran for #{other}")
  end

  defmodule Malformed do
    @behaviour Catalog
    @impl true
    def capabilities,
      do: %{tools: [], resources: [%ResourceSpec{uri: "mal://x", name: "x"}], prompts: []}

    @impl true
    def read_resource("mal://x"), do: {:ok, [%{text: "no uri"}]}
  end

  defmodule Empty do
    @behaviour Catalog
    @impl true
    def capabilities, do: %{tools: [], resources: [], prompts: []}
  end

  defp state(catalog, opts \\ []), do: Server.new([catalog: catalog] ++ opts)

  defp call(state, method, params, meta \\ @modern) do
    {_, r} =
      Server.handle_message(state, %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => method,
        "params" => Map.put(params, "_meta", meta)
      })

    r
  end

  describe "the specs" do
    test "a ResourceSpec needs a uri and a name; a template needs a uri_template and a name" do
      assert_raise ArgumentError, fn -> struct!(ResourceSpec, name: "x") end
      assert_raise ArgumentError, fn -> struct!(ResourceSpec, uri: "u://x") end
      assert_raise ArgumentError, fn -> struct!(ResourceTemplateSpec, name: "x") end
      assert %ResourceSpec{title: nil, size: nil} = %ResourceSpec{uri: "u://x", name: "x"}
    end
  end

  describe "the catalog contract" do
    test "the single readers split one list into resources and templates, each sorted on its key" do
      assert Enum.map(Catalog.resources(Injected), & &1.uri) ==
               ~w(injected://only-here/a injected://only-here/m injected://only-here/z)

      assert Enum.map(Catalog.templates(Injected), & &1.uri_template) ==
               ~w(injected://only-here/by-id/{id} injected://only-here/tree/{+path} injected://only-here/{name}.txt)
    end

    test "validate/1 refuses a resources entry that is neither spec, by name" do
      defmodule Loose do
        def capabilities,
          do: %{tools: [], resources: [%{"uri" => "x://y", "name" => "y"}], prompts: []}
      end

      assert {:error, message} = Catalog.validate(Loose)
      assert message =~ "ResourceSpec"
      assert message =~ ":resources"
    end

    test "validate/1 refuses a catalog that lists a resource and cannot read one" do
      defmodule Unreadable do
        def capabilities,
          do: %{tools: [], resources: [%ResourceSpec{uri: "x://y", name: "y"}], prompts: []}
      end

      assert {:error, message} = Catalog.validate(Unreadable)
      assert message =~ "read_resource/1"
    end

    test "validate/1 accepts an empty resources list without a reader" do
      assert :ok = Catalog.validate(Empty)
    end

    # Found by a review lane: two entries with one uri passed validate/1, and a walk at
    # page_size 1 dropped the second while page_size 50 showed both -- what a client saw
    # depended on the page size, in a static list, which is the gap the codec exists to
    # prevent. The codec's premise is a canonical key; the catalog is where it is enforced.
    test "validate/1 refuses a repeated uri or uri_template, by name" do
      defmodule Twice do
        def capabilities,
          do: %{
            tools: [],
            resources: [
              %ResourceSpec{uri: "d://a", name: "one"},
              %ResourceSpec{uri: "d://b", name: "b"},
              %ResourceSpec{uri: "d://a", name: "two"}
            ],
            prompts: []
          }

        def read_resource(uri), do: {:ok, [%{uri: uri, text: ""}]}
      end

      assert {:error, message} = Catalog.validate(Twice)
      assert message =~ "d://a"
      assert message =~ "more than once"

      defmodule TwiceTemplate do
        def capabilities,
          do: %{
            tools: [],
            resources: [
              %ResourceTemplateSpec{uri_template: "d://{x}", name: "one"},
              %ResourceTemplateSpec{uri_template: "d://{x}", name: "two"}
            ],
            prompts: []
          }

        def read_resource(uri), do: {:ok, [%{uri: uri, text: ""}]}
      end

      assert {:error, message} = Catalog.validate(TwiceTemplate)
      assert message =~ "d://{x}"
    end

    test "validate/1 refuses a catalog that lists only a template and cannot read one" do
      defmodule TemplateOnly do
        def capabilities,
          do: %{
            tools: [],
            resources: [%ResourceTemplateSpec{uri_template: "t://{x}", name: "t"}],
            prompts: []
          }
      end

      assert {:error, message} = Catalog.validate(TemplateOnly)
      assert message =~ "read_resource/1"
      assert message =~ "template"
    end
  end

  describe "the capability" do
    test "server/discover and initialize advertise resources with both schema sub-keys false" do
      for method <- ["server/discover", "initialize"] do
        {_, r} =
          Server.handle_message(state(Injected), %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => method,
            "params" => %{"protocolVersion" => "2025-11-25"}
          })

        assert r["result"]["capabilities"]["resources"] ==
                 %{"listChanged" => false, "subscribe" => false}
      end
    end
  end

  describe "resources/list" do
    test "advertises every resource the catalog names, sorted by uri, with the cacheable fields" do
      r = call(state(Injected), "resources/list", %{})
      result = r["result"]

      assert Enum.map(result["resources"], & &1["uri"]) ==
               ~w(injected://only-here/a injected://only-here/m injected://only-here/z)

      [a | _] = result["resources"]

      assert a == %{
               "uri" => "injected://only-here/a",
               "name" => "a",
               "title" => "A",
               "description" => "the first",
               "mimeType" => "text/plain",
               "size" => 3
             }

      # An optional field the spec leaves out is left out, not sent as null.
      assert Map.keys(List.last(result["resources"])) == ["name", "uri"]
      assert result["ttlMs"] == 0
      assert result["cacheScope"] == "private"
      assert result["resultType"] == "complete"
      refute Map.has_key?(result, "nextCursor")
    end

    test "a template is never in resources/list" do
      r = call(state(Injected), "resources/list", %{})
      refute Enum.any?(r["result"]["resources"], &Map.has_key?(&1, "uriTemplate"))
    end

    test "paginates by page_size with an opaque cursor that walks the whole list once" do
      s = state(Injected, page_size: 2)
      first = call(s, "resources/list", %{})["result"]
      assert length(first["resources"]) == 2
      assert is_binary(first["nextCursor"])
      second = call(s, "resources/list", %{"cursor" => first["nextCursor"]})["result"]
      assert Enum.map(second["resources"], & &1["name"]) == ["z"]
      refute Map.has_key?(second, "nextCursor")
    end

    test "a malformed cursor and another list's cursor are each invalid params, named" do
      s = state(Injected)
      r = call(s, "resources/list", %{"cursor" => "not-a-cursor"})
      assert r["error"]["code"] == -32_602
      assert r["error"]["message"] =~ "cursor"
      assert r["error"]["message"] =~ "malformed"

      r = call(s, "resources/list", %{"cursor" => Cursor.encode(:tools, "x")})
      assert r["error"]["code"] == -32_602
      assert r["error"]["message"] =~ "tools"

      r = call(s, "resources/list", %{"cursor" => 5})
      assert r["error"]["code"] == -32_602
    end

    test "the resources ttl and scope are the server's options, defaulting non-permissive" do
      r =
        call(
          state(Injected, resources_ttl_ms: 30_000, resources_cache_scope: "public"),
          "resources/list",
          %{}
        )

      assert r["result"]["ttlMs"] == 30_000
      assert r["result"]["cacheScope"] == "public"
    end

    test "under 2025-11-25 the result carries the list and no modern envelope" do
      r = call(state(Injected), "resources/list", %{}, @legacy)
      assert length(r["result"]["resources"]) == 3
      refute Map.has_key?(r["result"], "resultType")
    end

    test "an empty catalog is an empty page" do
      assert %{"resources" => []} = call(state(Empty), "resources/list", %{})["result"]
    end
  end

  describe "resources/templates/list" do
    test "advertises every template, sorted by uriTemplate, paginated by the same codec" do
      r = call(state(Injected), "resources/templates/list", %{})["result"]

      assert r["resourceTemplates"] == [
               %{
                 "uriTemplate" => "injected://only-here/by-id/{id}",
                 "name" => "by-id",
                 "mimeType" => "application/json"
               },
               %{"uriTemplate" => "injected://only-here/tree/{+path}", "name" => "tree"},
               %{"uriTemplate" => "injected://only-here/{name}.txt", "name" => "dotted"}
             ]

      assert r["resultType"] == "complete"

      s = state(Injected, page_size: 2)
      first = call(s, "resources/templates/list", %{})["result"]
      assert [%{"name" => "by-id"}, %{"name" => "tree"}] = first["resourceTemplates"]
      second = call(s, "resources/templates/list", %{"cursor" => first["nextCursor"]})["result"]
      assert [%{"name" => "dotted"}] = second["resourceTemplates"]
      refute Map.has_key?(second, "nextCursor")
    end

    test "a resources/list cursor sent to templates/list is refused by kind" do
      s = state(Injected, page_size: 2)
      first = call(s, "resources/list", %{})["result"]
      r = call(s, "resources/templates/list", %{"cursor" => first["nextCursor"]})
      assert r["error"]["code"] == -32_602
      assert r["error"]["message"] =~ "resources"
    end
  end

  describe "resources/read" do
    test "a listed uri is read through the catalog's reader; text contents as given" do
      r = call(state(Injected), "resources/read", %{"uri" => "injected://only-here/a"})["result"]

      assert r["contents"] == [
               %{"uri" => "injected://only-here/a", "text" => "abc", "mimeType" => "text/plain"}
             ]

      assert r["ttlMs"] == 0
      assert r["cacheScope"] == "private"
      assert r["resultType"] == "complete"
    end

    test "blob contents are base64 on the wire, from raw bytes at the reader" do
      r = call(state(Injected), "resources/read", %{"uri" => "injected://only-here/m"})["result"]
      assert [%{"uri" => "injected://only-here/m", "blob" => blob}] = r["contents"]
      assert Base.decode64!(blob) == <<0, 255, 1>>
    end

    test "a uri a listed template matches is read: {var} one segment, {+var} across segments" do
      s = state(Injected)
      r = call(s, "resources/read", %{"uri" => "injected://only-here/by-id/42"})["result"]
      assert [%{"text" => ~s({"id":"42"})}] = r["contents"]

      r = call(s, "resources/read", %{"uri" => "injected://only-here/tree/x/y/z"})["result"]
      assert [%{"text" => "x/y/z"}] = r["contents"]

      # {id} is one segment: a slash inside it is not a match, so the uri is not listed.
      r = call(s, "resources/read", %{"uri" => "injected://only-here/by-id/4/2"})
      assert r["error"]["code"] == -32_002

      # And a segment, not nothing: a resource with an empty id is not a resource the
      # template names. Stated in the matcher's doc; pinned here.
      r = call(s, "resources/read", %{"uri" => "injected://only-here/by-id/"})
      assert r["error"]["code"] == -32_002

      # A literal character of the template is literal: the "." of ".txt" is not "any".
      r = call(s, "resources/read", %{"uri" => "injected://only-here/notes.txt"})["result"]
      assert [%{"text" => "notes.txt"}] = r["contents"]
      r = call(s, "resources/read", %{"uri" => "injected://only-here/notes-txt"})
      assert r["error"]["code"] == -32_002
    end

    test "a uri neither listed nor matched is -32002 with the uri as data, before any host code" do
      r = call(state(Injected), "resources/read", %{"uri" => "injected://elsewhere"})
      assert r["error"]["code"] == -32_002
      assert r["error"]["message"] =~ "Resource not found"
      assert r["error"]["data"] == %{"uri" => "injected://elsewhere"}
    end

    test "a reader's error is -32002 carrying the reason as data" do
      r = call(state(Injected), "resources/read", %{"uri" => "injected://only-here/z"})
      assert r["error"]["code"] == -32_002
      assert r["error"]["data"] == %{"uri" => "injected://only-here/z", "reason" => "z is gone"}
    end

    test "a malformed reader answer is -32603 naming the defect, never a crash or a reshaped payload" do
      r = call(state(Malformed), "resources/read", %{"uri" => "mal://x"})
      assert r["error"]["code"] == -32_603
      assert r["error"]["message"] =~ "read_resource/1"
      assert r["error"]["message"] =~ "uri"
    end

    test "a missing or non-string uri is invalid params, and so is a request with no params at all" do
      s = state(Injected)
      assert call(s, "resources/read", %{})["error"]["code"] == -32_602
      assert call(s, "resources/read", %{"uri" => 1})["error"]["code"] == -32_602

      {_, r} =
        Server.handle_message(s, %{"jsonrpc" => "2.0", "id" => 9, "method" => "resources/read"})

      assert r["error"]["code"] == -32_602
    end

    test "under 2025-11-25 the contents come without the modern envelope" do
      r = call(state(Injected), "resources/read", %{"uri" => "injected://only-here/a"}, @legacy)
      assert [%{"text" => "abc"}] = r["result"]["contents"]
      refute Map.has_key?(r["result"], "resultType")
    end
  end

  describe "new/1 options" do
    test "page_size must be a positive integer; the ttl and scope pair as the tools pair" do
      for bad <- [0, -1, 1.5, "2", nil] do
        assert_raise ArgumentError, ~r/:page_size/, fn -> state(Empty, page_size: bad) end
      end

      for bad <- [-1, "0"] do
        assert_raise ArgumentError, ~r/:resources_ttl_ms/, fn ->
          state(Empty, resources_ttl_ms: bad)
        end
      end

      assert_raise ArgumentError, ~r/:resources_cache_scope/, fn ->
        state(Empty, resources_cache_scope: :public)
      end

      assert %{page_size: 50} = state(Empty)
    end
  end
end
