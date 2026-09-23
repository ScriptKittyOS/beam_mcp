# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Schema do
  @moduledoc """
  Validates `tools/call` arguments against the JSON Schema the server advertises.

  Advertising a schema is not enforcing one. A server that returns `"required"` and
  `"additionalProperties" => false` in `tools/list` and then dispatches whatever arrives has
  published a contract it does not keep.

  That gap is exploitable, and the exploit does not need a clever payload. If a host merges
  defaults into the argument map with atom keys while unrecognised **string** keys survive
  validation, the two never collide in the map and both reach whatever serialises the result --
  where the caller's value can win. A client then supplies its own value for a field the host
  believed it controlled, and reads it back as though the host had set it.

  So this module refuses rather than guesses, and the server enforces the same schema it
  advertised rather than a second one compiled in beside it.

  ## What is enforced, at every depth

  `type` (one type or a list; `string`, `integer`, `number`, `boolean`, `object`, `array`,
  `null`), `enum`, `const`; for objects `properties`, `required`, `additionalProperties`
  (`false`, or a schema every other property must meet), `minProperties`, `maxProperties`; for
  arrays `items`, `minItems`, `maxItems`, `uniqueItems`; for strings `minLength`, `maxLength`
  (counted in code points) and `pattern`; for numbers `minimum`, `maximum`,
  `exclusiveMinimum`, `exclusiveMaximum`. Annotations are allowed and change nothing:
  `title`, `description`, `default`, `examples`, `format`, `readOnly`, `writeOnly`,
  `deprecated`, `$schema`, `$id`, `$comment`, and any key beginning `x-` (`x-mcp-header`
  among them).

  Two readings are stricter than JSON Schema's, so that a host never receives what its own
  types would not expect, and are stated here rather than discovered. `integer` means a number
  sent without a fraction or exponent: `1.0` is a `number` and not an `integer` (JSON Schema
  counts it an integer). `pattern` is compiled by the BEAM's PCRE with ECMA-262's character
  classes and anchors (`\\d`, `\\w` and `\\s` are ASCII, `$` matches only at the end, never
  before a trailing newline), so an allowlist pattern admits what a client's own validator
  would; constructs PCRE and ECMA-262 read differently beyond those are the host's to avoid.
  `enum`, `const` and `uniqueItems` compare as JSON does: `1` and `1.0` are the same value.

  **Any other keyword is refused, not ignored**: a schema using `oneOf`, `$ref`, `if`, or
  anything else outside the list above is refused when the catalog is validated at startup,
  and a call against such a schema is refused rather than dispatched. A schema the server
  advertises is therefore always one it enforces in full.
  """

  @type result :: :ok | {:error, String.t()}

  # PCRE with ECMA-262's classes and anchors: `:unicode` without `:ucp` keeps `\d`, `\w` and
  # `\s` ASCII, and `:dollar_endonly` keeps `$` from matching before a trailing newline.
  @pattern_options [:unicode, :dollar_endonly]

  @enforced [
    "type",
    "enum",
    "const",
    "properties",
    "required",
    "additionalProperties",
    "minProperties",
    "maxProperties",
    "items",
    "minItems",
    "maxItems",
    "uniqueItems",
    "minLength",
    "maxLength",
    "pattern",
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum"
  ]
  @annotations [
    "title",
    "description",
    "default",
    "examples",
    "format",
    "readOnly",
    "writeOnly",
    "deprecated",
    "$schema",
    "$id",
    "$comment"
  ]
  @types ["string", "integer", "number", "boolean", "object", "array", "null"]

  @doc """
  Validates `arguments` against `schema`.

  Returns `:ok`, or `{:error, reason}` naming the offending property (a nested one by its
  path, `opts.mode` or `tags[1]`). A schema that uses a keyword outside the enforced set is an
  error too: nothing is dispatched against a schema this module cannot enforce in full.
  """
  @spec validate(map(), map()) :: result()
  def validate(arguments, schema) when is_map(arguments) and is_map(schema) do
    with :ok <- check_schema(schema) do
      check(arguments, compile_patterns(schema), [])
    end
  end

  def validate(_arguments, _schema), do: {:error, "arguments must be an object"}

  @doc false
  # The schema itself: every keyword enforced or an annotation, every value well-formed. Read
  # by `BeamMCP.Catalog.validate/1` at startup, and by `validate/2` on every call, so a
  # catalog whose answer changes after startup cannot advertise what is not enforced either.
  @spec check_schema(term()) :: result()
  def check_schema(schema), do: check_schema(schema, "the schema")

  defp check_schema(schema, where) when is_map(schema) and not is_struct(schema) do
    Enum.reduce_while(schema, :ok, fn {key, value}, :ok ->
      continue_or_halt(check_keyword(key, value, where))
    end)
  end

  defp check_schema(_schema, where), do: {:error, "#{where} must be a JSON object"}

  defp check_keyword(key, _value, _where) when key in @annotations, do: :ok

  defp check_keyword("x-" <> _, _value, _where), do: :ok

  defp check_keyword("type", type, where) do
    types = List.wrap(type)

    if types != [] and proper_list?(types) and Enum.all?(types, &(&1 in @types)),
      do: :ok,
      else: {:error, "#{where}: type must name JSON types (#{Enum.join(@types, ", ")})"}
  end

  # The values a refusal displays and a comparison reads: JSON values only, so neither can
  # raise on a host's term (a tuple in an enum has no JSON text).
  defp check_keyword("enum", values, where) do
    if is_list(values) and json_value?(values),
      do: :ok,
      else: {:error, "#{where}: enum must be a list of JSON values"}
  end

  defp check_keyword("const", value, where) do
    if json_value?(value), do: :ok, else: {:error, "#{where}: const must be a JSON value"}
  end

  # A property's name is the key a client's string meets: anything else could never match,
  # so the property would be advertised and never checked.
  defp check_keyword("properties", properties, where)
       when is_map(properties) and not is_struct(properties) do
    Enum.reduce_while(properties, :ok, fn
      {name, sub}, :ok when is_binary(name) ->
        continue_or_halt(check_schema(sub, "#{where}, property #{name}"))

      {name, _sub}, :ok ->
        {:halt, {:error, "#{where}: property name #{inspect(name)} is not a string"}}
    end)
  end

  defp check_keyword("properties", _, where),
    do: {:error, "#{where}: properties must be an object"}

  defp check_keyword("required", required, where) do
    if proper_list?(required) and Enum.all?(required, &is_binary/1),
      do: :ok,
      else: {:error, "#{where}: required must be a list of property names"}
  end

  defp check_keyword("additionalProperties", value, _where) when is_boolean(value), do: :ok

  defp check_keyword("additionalProperties", value, where),
    do: check_schema(value, "#{where}, additionalProperties")

  defp check_keyword("items", value, where), do: check_schema(value, "#{where}, items")

  defp check_keyword("uniqueItems", value, where) do
    if is_boolean(value), do: :ok, else: {:error, "#{where}: uniqueItems must be a boolean"}
  end

  defp check_keyword("pattern", pattern, where) when is_binary(pattern) do
    case Regex.compile(pattern, @pattern_options) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "#{where}: pattern is not a valid regular expression"}
    end
  end

  defp check_keyword("pattern", _, where), do: {:error, "#{where}: pattern must be a string"}

  defp check_keyword(key, value, where)
       when key in [
              "minProperties",
              "maxProperties",
              "minItems",
              "maxItems",
              "minLength",
              "maxLength"
            ] do
    if is_integer(value) and value >= 0,
      do: :ok,
      else: {:error, "#{where}: #{key} must be a non-negative integer"}
  end

  defp check_keyword(key, value, where)
       when key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] do
    if is_number(value), do: :ok, else: {:error, "#{where}: #{key} must be a number"}
  end

  defp check_keyword(key, _value, _where) when key in @enforced, do: :ok

  defp check_keyword(key, _value, where) when is_binary(key),
    do: {:error, "#{where} uses #{key}, which this server does not enforce"}

  defp check_keyword(key, _value, where),
    do: {:error, "#{where} uses #{inspect(key)}, which is not a JSON keyword"}

  defp proper_list?([]), do: true
  defp proper_list?([_ | tail]), do: proper_list?(tail)
  defp proper_list?(_), do: false

  defp json_value?(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: true

  defp json_value?(nil), do: true

  defp json_value?(list) when is_list(list),
    do: proper_list?(list) and Enum.all?(list, &json_value?/1)

  defp json_value?(value) when is_map(value) and not is_struct(value),
    do: Enum.all?(value, fn {key, sub} -> is_binary(key) and json_value?(sub) end)

  defp json_value?(_value), do: false

  # Each pattern compiled once per call, not once per value it is matched against: a schema
  # already checked, so every pattern compiles.
  defp compile_patterns(schema) do
    Map.new(schema, fn
      {"pattern", pattern} -> {"pattern", Regex.compile!(pattern, @pattern_options)}
      {"properties", properties} -> {"properties", Map.new(properties, &compile_property/1)}
      {"additionalProperties", %{} = sub} -> {"additionalProperties", compile_patterns(sub)}
      {"items", sub} -> {"items", compile_patterns(sub)}
      other -> other
    end)
  end

  defp compile_property({name, sub}), do: {name, compile_patterns(sub)}

  # The value against the schema. `path` is the property path so far, innermost last.
  defp check(value, schema, path) do
    with :ok <- check_type(value, Map.get(schema, "type"), path),
         :ok <- check_enum(value, schema, path),
         :ok <- check_const(value, schema, path) do
      check_shape(value, schema, path)
    end
  end

  defp check_shape(value, schema, path) when is_map(value) do
    properties = Map.get(schema, "properties", %{})

    with :ok <- check_required(value, Map.get(schema, "required", []), path),
         :ok <- check_additional(value, properties, schema, path),
         :ok <- check_count(map_size(value), schema, "Properties", "properties", path) do
      check_properties(value, properties, path)
    end
  end

  defp check_shape(value, schema, path) when is_list(value) do
    with :ok <- check_count(length(value), schema, "Items", "items", path),
         :ok <- check_unique(value, schema, path) do
      check_items(value, Map.get(schema, "items"), path)
    end
  end

  defp check_shape(value, schema, path) when is_binary(value) do
    with :ok <- check_count(code_points(value), schema, "Length", "characters", path) do
      check_pattern(value, Map.get(schema, "pattern"), path)
    end
  end

  defp check_shape(value, schema, path) when is_number(value),
    do: check_range(value, schema, path)

  defp check_shape(_value, _schema, _path), do: :ok

  defp check_required(object, required, path) do
    case Enum.reject(required, &Map.has_key?(object, &1)) do
      [] -> :ok
      missing -> {:error, "missing required propert#{plural(missing)}: #{names(path, missing)}"}
    end
  end

  defp check_additional(object, properties, schema, path) do
    extra = object |> Map.keys() |> Enum.reject(&Map.has_key?(properties, &1))

    case Map.get(schema, "additionalProperties", true) do
      false when extra != [] ->
        {:error, "unknown propert#{plural(extra)}: #{names(path, extra)}"}

      %{} = sub ->
        Enum.reduce_while(extra, :ok, fn key, :ok ->
          continue_or_halt(check(Map.fetch!(object, key), sub, path ++ [key]))
        end)

      _ ->
        :ok
    end
  end

  defp check_properties(object, properties, path) do
    Enum.reduce_while(object, :ok, fn {key, value}, :ok ->
      case Map.fetch(properties, key) do
        {:ok, sub} -> continue_or_halt(check(value, sub, path ++ [key]))
        :error -> {:cont, :ok}
      end
    end)
  end

  defp check_items(_list, nil, _path), do: :ok

  defp check_items(list, sub, path) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      continue_or_halt(check(value, sub, path ++ [index]))
    end)
  end

  defp check_unique(list, schema, path) do
    if Map.get(schema, "uniqueItems") == true and
         length(Enum.uniq_by(list, &json_form/1)) != length(list),
       do: {:error, "#{label(path)} must not repeat items"},
       else: :ok
  end

  # min/max counts share one shape: minItems/maxItems, minLength/maxLength,
  # minProperties/maxProperties.
  defp check_count(count, schema, suffix, noun, path) do
    min = Map.get(schema, "min" <> suffix)
    max = Map.get(schema, "max" <> suffix)

    cond do
      is_integer(min) and count < min ->
        {:error, "#{label(path)} must have at least #{min} #{noun}"}

      is_integer(max) and count > max ->
        {:error, "#{label(path)} must have at most #{max} #{noun}"}

      true ->
        :ok
    end
  end

  # JSON Schema counts a string's length in code points (not graphemes, not bytes); the
  # value is valid UTF-8, since the decoder refused anything else.
  defp code_points(string), do: for(<<_::utf8 <- string>>, reduce: 0, do: (n -> n + 1))

  defp check_pattern(_value, nil, _path), do: :ok

  defp check_pattern(value, pattern, path) do
    if Regex.match?(pattern, value),
      do: :ok,
      else: {:error, "#{label(path)} does not match the required pattern"}
  end

  defp check_type(_value, nil, _path), do: :ok

  defp check_type(value, type, path) do
    types = List.wrap(type)

    if Enum.any?(types, &type?(value, &1)),
      do: :ok,
      else: {:error, "#{label(path)} must be of type #{Enum.join(types, " or ")}"}
  end

  defp type?(value, "string"), do: is_binary(value)
  defp type?(value, "integer"), do: is_integer(value)
  defp type?(value, "number"), do: is_number(value)
  defp type?(value, "boolean"), do: is_boolean(value)
  defp type?(value, "object"), do: is_map(value)
  defp type?(value, "array"), do: is_list(value)
  defp type?(value, "null"), do: is_nil(value)

  defp check_enum(value, schema, path) do
    case Map.fetch(schema, "enum") do
      {:ok, allowed} ->
        if Enum.any?(allowed, &(json_form(&1) === json_form(value))),
          do: :ok,
          else: {:error, "#{label(path)} must be one of: #{join(allowed)}"}

      :error ->
        :ok
    end
  end

  defp check_const(value, schema, path) do
    case Map.fetch(schema, "const") do
      {:ok, expected} ->
        if json_form(expected) === json_form(value),
          do: :ok,
          else: {:error, "#{label(path)} must be #{display(expected)}"}

      :error ->
        :ok
    end
  end

  # A value as JSON compares it: a float with no fraction is the integer it equals (`1.0` is
  # `1`), at every depth; everything else is itself.
  defp json_form(value) when is_float(value) do
    whole = trunc(value)
    if whole == value, do: whole, else: value
  end

  defp json_form(value) when is_list(value), do: Enum.map(value, &json_form/1)
  defp json_form(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, json_form(v)} end)
  defp json_form(value), do: value

  # Each bound: its keyword, the comparison a value must pass, and the operator the refusal names.
  @bounds [
    {"minimum", &Kernel.>=/2, ">="},
    {"maximum", &Kernel.<=/2, "<="},
    {"exclusiveMinimum", &Kernel.>/2, ">"},
    {"exclusiveMaximum", &Kernel.</2, "<"}
  ]

  defp check_range(value, schema, path) do
    Enum.find_value(@bounds, :ok, fn {key, passes?, operator} ->
      bound = Map.get(schema, key)

      if is_number(bound) and not passes?.(value, bound),
        do: {:error, "#{label(path)} must be #{operator} #{bound}"}
    end)
  end

  # Extracted so the reduce bodies nest two deep rather than three. A passing check continues
  # the fold, a failing one halts it carrying the error.
  defp continue_or_halt(:ok), do: {:cont, :ok}
  defp continue_or_halt(error), do: {:halt, error}

  defp label([]), do: "arguments"
  defp label(path), do: Enum.reduce(path, "", &segment/2)

  defp segment(index, acc) when is_integer(index), do: acc <> "[#{index}]"
  defp segment(key, ""), do: key
  defp segment(key, acc), do: acc <> "." <> key

  defp names(path, keys), do: Enum.map_join(keys, ", ", &label(path ++ [&1]))

  # Schema values rendered for a message, whatever JSON they are: a string as itself, anything
  # else as its JSON text (a map or a list in an enum has no to_string/1).
  defp display(value) when is_binary(value), do: value
  defp display(value), do: Jason.encode!(value)

  defp plural([_]), do: "y"
  defp plural(_), do: "ies"
  defp join(values), do: Enum.map_join(values, ", ", &display/1)
end
