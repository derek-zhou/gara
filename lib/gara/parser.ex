defmodule Gara.Parser do
  use Md.Parser

  alias Md.Parser.Syntax.Void

  require Logger

  @default_syntax Map.put(Void.syntax(), :settings, Void.settings())

  @syntax @default_syntax
          |> Map.merge(%{
            substitute: [
              {"<", %{text: "&lt;"}},
              {"&", %{text: "&amp;"}}
            ],
            escape: [
              {<<92>>, %{}}
            ],
            comment: [
              {"<!--", %{closing: "-->"}}
            ],
            flush: [
              {"---", %{tag: :hr, rewind: :flip_flop}},
              {"  \n", %{tag: :br}},
              {"  \n", %{tag: :br}},
              {"  \r\n", %{tag: :br}},
              {"  \r\n", %{tag: :br}}
            ],
            magnet: [
              {"@", %{transform: &Gara.Parser.mention_tag/2}},
              {"#", %{transform: &Gara.Parser.hash_tag/2}}
            ],
            block: [
              {"```", %{tag: [:pre, :code], pop: %{code: :class}}}
            ],
            shift: [
              {"    ", %{tag: [:div, :code], attributes: %{class: "pre"}}}
            ],
            pair: [
              {"![",
               %{
                 tag: :img,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 outer: {:attribute, {:src, :title}}
               }},
              {"!![",
               %{
                 tag: :figure,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 inner_tag: :img,
                 outer: {:tag, {:figcaption, :src}}
               }},
              {"?[",
               %{
                 tag: :abbr,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 outer: {:attribute, :title}
               }},
              {"[",
               %{
                 tag: :a,
                 closing: "]",
                 inner_opening: "(",
                 inner_closing: ")",
                 disclosure_opening: "[",
                 disclosure_closing: "]",
                 outer: {:attribute, :href}
               }}
            ],
            paragraph: [
              # nested
              {">", %{tag: [:blockquote, :p]}}
            ],
            list:
              [
                {"- ", %{tag: :li, outer: :ul}},
                {"* ", %{tag: :li, outer: :ul}},
                {"+ ", %{tag: :li, outer: :ul}}
              ] ++ Enum.map(0..9, &{"#{&1}. ", %{tag: :li, outer: :ol}}),
            brace: [
              {"*", %{tag: :b}},
              {"_", %{tag: :i}},
              {"**", %{tag: :strong, attributes: %{class: "red"}}},
              {"__", %{tag: :em}},
              {"~", %{tag: :s}},
              {"~~", %{tag: :del}},
              {"``", %{tag: :span, mode: :raw, attributes: %{class: "code-inline"}}},
              {"`", %{tag: :code, mode: :raw, attributes: %{class: "code-inline"}}},
              {"[^", %{closing: "]", tag: :b, mode: :raw}}
            ]
          })

  def hash_tag(md, text) do
    {:a, %{href: "#msg_#{text}", class: "hash-tag"}, [md <> text]}
  end

  def mention_tag(md, text) do
    {:span, %{class: "mention-tag", "data-mention": text}, [md <> text]}
  end
end
