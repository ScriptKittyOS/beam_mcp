# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PromptsTest do
  @moduledoc """
  The prompts primitive: `prompts/list`, `prompts/get`, the `prompts` capability, and the one
  validation path prompt arguments share with tool arguments. The method set is the
  2026-07-28 schema's, derived and recorded before this file was written; each method answered
  `-32601` on the tree it was added to.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.{Catalog, Cursor, PromptArgument, PromptSpec, Server}

  @modern %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }
  @legacy %{"io.modelcontextprotocol/protocolVersion" => "2025-11-25"}

  # Entries that exist in no other catalog of this suite: honoured or not, never by
  # coincidence.
  defmodule Injected do
    @behaviour Catalog

    @impl true
    def capabilities do
      %{
        tools: [],
        resources: [],
        prompts: [
          %PromptSpec{name: "zeta", description: "last"},
          %PromptSpec{
            name: "greet",
            title: "Greeting",
            description: "Greets someone.",
            arguments: [
              %PromptArgument{name: "who", description: "whom to greet", required: true},
              %PromptArgument{name: "tone", title: "Tone"}
            ]
          },
          %PromptSpec{name: "mid"}
        ]
      }
    end

    @impl true
    def get_prompt("greet", %{who: who} = args) do
      tone = Map.get(args, :tone, "warm")

      {:ok,
       %{
         description: "A #{tone} greeting for #{who}",
         messages: [
           %{role: :user, text: "Say hello to #{who}, #{tone}ly."},
           %{role: :assistant, text: "Hello, #{who}!"}
         ]
       }}
    end

    def get_prompt("mid", _args), do: {:ok, %{messages: [%{role: :user, text: "mid"}]}}
    def get_prompt("zeta", _args), do: {:error, "zeta cannot be rendered"}
    def get_prompt(other, _args), do: raise("host code ran for #{other}")
  end

  defmodule Malformed do
    @behaviour Catalog
    @impl true
    def capabilities, do: %{tools: [], resources: [], prompts: [%PromptSpec{name: "bad"}]}
    @impl true
    def get_prompt("bad", _), do: {:ok, %{messages: [%{role: :system, text: "no such role"}]}}
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
    test "a PromptSpec needs a name; an argument needs a name and is optional by default" do
      assert_raise ArgumentError, fn -> struct!(PromptSpec, title: "x") end
      assert_raise ArgumentError, fn -> struct!(PromptArgument, description: "x") end
      assert %PromptSpec{arguments: []} = %PromptSpec{name: "p"}
      assert %PromptArgument{required: false} = %PromptArgument{name: "a"}
    end

    # Acceptance 3: the argument list becomes the tools validator's input -- one schema
    # shape, derived by a pure function, so there is one validator and not two.
    test "argument_schema/1 derives the JSON Schema the tools validator runs" do
      spec = %PromptSpec{
        name: "greet",
        arguments: [
          %PromptArgument{name: "who", description: "whom", required: true},
          %PromptArgument{name: "tone"}
        ]
      }

      assert PromptSpec.argument_schema(spec) == %{
               "type" => "object",
               "properties" => %{
                 "who" => %{"type" => "string", "description" => "whom"},
                 "tone" => %{"type" => "string"}
               },
               "required" => ["who"],
               "additionalProperties" => false
             }

      assert PromptSpec.argument_schema(%PromptSpec{name: "bare"}) == %{
               "type" => "object",
               "properties" => %{},
               "required" => [],
               "additionalProperties" => false
             }
    end
  end

  describe "the catalog contract" do
    test "the single reader sorts prompts by name; fetch finds one" do
      assert Enum.map(Catalog.prompts(Injected), & &1.name) == ~w(greet mid zeta)
      assert {:ok, %PromptSpec{name: "mid"}} = Catalog.fetch_prompt(Injected, "mid")
      assert :error = Catalog.fetch_prompt(Injected, "nope")
    end

    test "validate/1 refuses a prompts entry that is not a PromptSpec, by name" do
      defmodule Loose do
        def capabilities, do: %{tools: [], resources: [], prompts: [%{name: "greet"}]}
      end

      assert {:error, message} = Catalog.validate(Loose)
      assert message =~ "PromptSpec"
      assert message =~ ":prompts"
    end

    test "validate/1 refuses a listed prompt without get_prompt/2, a repeated name, and a repeated argument" do
      defmodule NoReader do
        def capabilities, do: %{tools: [], resources: [], prompts: [%PromptSpec{name: "p"}]}
      end

      assert {:error, message} = Catalog.validate(NoReader)
      assert message =~ "get_prompt/2"

      defmodule Twice do
        def capabilities,
          do: %{
            tools: [],
            resources: [],
            prompts: [%PromptSpec{name: "p"}, %PromptSpec{name: "p"}]
          }

        def get_prompt(_, _), do: {:ok, %{messages: []}}
      end

      assert {:error, message} = Catalog.validate(Twice)
      assert message =~ ~s("p")
      assert message =~ "more than once"

      defmodule TwiceArg do
        def capabilities,
          do: %{
            tools: [],
            resources: [],
            prompts: [
              %PromptSpec{
                name: "p",
                arguments: [%PromptArgument{name: "a"}, %PromptArgument{name: "a"}]
              }
            ]
          }

        def get_prompt(_, _), do: {:ok, %{messages: []}}
      end

      assert {:error, message} = Catalog.validate(TwiceArg)
      assert message =~ ~s("a")
      assert message =~ "argument"
    end

    test "validate/1 accepts an empty prompts list without a reader" do
      assert :ok = Catalog.validate(Empty)
    end
  end

  describe "the capability" do
    test "server/discover and initialize advertise prompts with listChanged false" do
      for method <- ["server/discover", "initialize"] do
        {_, r} =
          Server.handle_message(state(Injected), %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => method,
            "params" => %{"protocolVersion" => "2025-11-25"}
          })

        assert r["result"]["capabilities"]["prompts"] == %{"listChanged" => false}
      end
    end
  end

  describe "prompts/list" do
    test "advertises every prompt sorted by name, arguments as the schema spells them, optional fields left off" do
      r = call(state(Injected), "prompts/list", %{})["result"]
      assert Enum.map(r["prompts"], & &1["name"]) == ~w(greet mid zeta)

      [greet, mid, _] = r["prompts"]

      assert greet == %{
               "name" => "greet",
               "title" => "Greeting",
               "description" => "Greets someone.",
               "arguments" => [
                 %{"name" => "who", "description" => "whom to greet", "required" => true},
                 %{"name" => "tone", "title" => "Tone", "required" => false}
               ]
             }

      assert mid == %{"name" => "mid"}
      assert r["ttlMs"] == 0
      assert r["cacheScope"] == "private"
      assert r["resultType"] == "complete"
      refute Map.has_key?(r, "nextCursor")
    end

    test "paginates by page_size with the shared codec; another list's cursor refused by kind" do
      s = state(Injected, page_size: 2)
      first = call(s, "prompts/list", %{})["result"]
      assert length(first["prompts"]) == 2
      second = call(s, "prompts/list", %{"cursor" => first["nextCursor"]})["result"]
      assert Enum.map(second["prompts"], & &1["name"]) == ["zeta"]
      refute Map.has_key?(second, "nextCursor")

      r = call(s, "prompts/list", %{"cursor" => Cursor.encode(:resources, "x")})
      assert r["error"]["code"] == -32_602
      assert r["error"]["message"] =~ "prompts"

      r = call(s, "prompts/list", %{"cursor" => "junk"})
      assert r["error"]["code"] == -32_602
    end

    test "the prompts ttl and scope are the server's options, defaulting non-permissive" do
      r =
        call(
          state(Injected, prompts_ttl_ms: 5_000, prompts_cache_scope: "public"),
          "prompts/list",
          %{}
        )["result"]

      assert r["ttlMs"] == 5_000
      assert r["cacheScope"] == "public"

      # The pairs are independent: a resources ttl does not leak into the prompts list.
      r = call(state(Injected, resources_ttl_ms: 9_000), "prompts/list", %{})["result"]
      assert r["ttlMs"] == 0
    end

    test "a params that is not an object is invalid params; under 2025-11-25 no modern envelope" do
      {_, r} =
        Server.handle_message(state(Injected), %{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "prompts/list",
          "params" => []
        })

      assert r["error"]["code"] == -32_602

      r = call(state(Injected), "prompts/list", %{}, @legacy)
      assert length(r["result"]["prompts"]) == 3
      refute Map.has_key?(r["result"], "resultType")
    end

    test "an empty catalog is an empty page" do
      assert %{"prompts" => []} = call(state(Empty), "prompts/list", %{})["result"]
    end
  end

  describe "prompts/get" do
    test "a listed prompt is rendered by the catalog's reader with the arguments keyed by the declared names" do
      r =
        call(state(Injected), "prompts/get", %{
          "name" => "greet",
          "arguments" => %{"who" => "Ada", "tone" => "brisk"}
        })["result"]

      assert r["description"] == "A brisk greeting for Ada"

      assert r["messages"] == [
               %{
                 "role" => "user",
                 "content" => %{"type" => "text", "text" => "Say hello to Ada, briskly."}
               },
               %{"role" => "assistant", "content" => %{"type" => "text", "text" => "Hello, Ada!"}}
             ]

      assert r["resultType"] == "complete"
      # GetPromptResult is not cacheable: no ttl, no scope.
      refute Map.has_key?(r, "ttlMs")
      refute Map.has_key?(r, "cacheScope")
    end

    test "an optional argument may be absent; a description absent from the answer is absent on the wire" do
      r =
        call(state(Injected), "prompts/get", %{"name" => "greet", "arguments" => %{"who" => "Bo"}})[
          "result"
        ]

      assert r["description"] == "A warm greeting for Bo"

      r = call(state(Injected), "prompts/get", %{"name" => "mid"})["result"]
      refute Map.has_key?(r, "description")
      assert [%{"role" => "user"}] = r["messages"]
    end

    test "a missing required argument, a non-string value and an undeclared argument are each -32602 by name, before the reader" do
      s = state(Injected)
      r = call(s, "prompts/get", %{"name" => "greet", "arguments" => %{}})
      assert r["error"]["code"] == -32_602
      assert r["error"]["message"] =~ "who"

      r = call(s, "prompts/get", %{"name" => "greet", "arguments" => %{"who" => 1}})
      assert r["error"]["code"] == -32_602

      r =
        call(s, "prompts/get", %{
          "name" => "greet",
          "arguments" => %{"who" => "x", "extra" => "y"}
        })

      assert r["error"]["code"] == -32_602
      assert r["error"]["message"] =~ "extra"

      r = call(s, "prompts/get", %{"name" => "greet", "arguments" => "who=x"})
      assert r["error"]["code"] == -32_602
    end

    test "an unknown prompt is -32602 with the name as data, before any host code" do
      r = call(state(Injected), "prompts/get", %{"name" => "nope"})
      assert r["error"]["code"] == -32_602
      assert r["error"]["message"] =~ "unknown prompt"
      assert r["error"]["data"] == %{"name" => "nope"}
    end

    test "a reader's error is -32602 carrying the reason as data" do
      r = call(state(Injected), "prompts/get", %{"name" => "zeta"})
      assert r["error"]["code"] == -32_602
      assert r["error"]["data"] == %{"name" => "zeta", "reason" => "zeta cannot be rendered"}
    end

    test "a malformed reader answer is -32603 naming the defect" do
      r = call(state(Malformed), "prompts/get", %{"name" => "bad"})
      assert r["error"]["code"] == -32_603
      assert r["error"]["message"] =~ "get_prompt/2"
      assert r["error"]["message"] =~ "role"
    end

    test "a missing or non-string name, and a request with no params, are invalid params" do
      s = state(Injected)
      assert call(s, "prompts/get", %{})["error"]["code"] == -32_602
      assert call(s, "prompts/get", %{"name" => 1})["error"]["code"] == -32_602

      {_, r} =
        Server.handle_message(s, %{"jsonrpc" => "2.0", "id" => 9, "method" => "prompts/get"})

      assert r["error"]["code"] == -32_602
    end

    test "under 2025-11-25 the messages come without the modern envelope" do
      r = call(state(Injected), "prompts/get", %{"name" => "mid"}, @legacy)
      assert [%{"role" => "user"}] = r["result"]["messages"]
      refute Map.has_key?(r["result"], "resultType")
    end
  end

  describe "acceptance 4: a caller-supplied argument name interns nothing" do
    # The tools path's bound, never written as a test before: measured here for both paths.
    test "10,000 distinct caller keys through prompts/get and tools/call leave the atom table where it was" do
      defmodule Keyed do
        @behaviour Catalog
        def capabilities do
          %{
            tools: [
              %BeamMCP.ToolSpec{
                name: :t,
                command_class: :observe,
                mode: :read_only,
                description: "t",
                input_schema: %{
                  "type" => "object",
                  "properties" => %{"k" => %{"type" => "string"}}
                }
              }
            ],
            resources: [],
            prompts: [%PromptSpec{name: "p", arguments: [%PromptArgument{name: "k"}]}]
          }
        end

        def get_prompt("p", _args), do: {:ok, %{messages: []}}
      end

      s = state(Keyed, dispatch: fn _, _, _ -> {:ok, "ok"} end)
      # Warm both paths once so any lazy interning of the package's own names is behind us.
      call(s, "prompts/get", %{"name" => "p", "arguments" => %{"k" => "v"}})
      call(s, "tools/call", %{"name" => "t", "arguments" => %{"k" => "v"}})
      before = :erlang.system_info(:atom_count)

      for i <- 1..10_000 do
        key = "caller-key-#{i}-#{System.unique_integer([:positive])}"
        call(s, "prompts/get", %{"name" => "p", "arguments" => %{key => "v"}})
        call(s, "tools/call", %{"name" => "t", "arguments" => %{key => "v"}})
      end

      assert :erlang.system_info(:atom_count) == before
    end
  end
end
