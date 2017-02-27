defmodule JSONAPI.View do
  @moduledoc """
  A View is simply a module that defines certain callbacks to configure proper
  rendering of your JSONAPI documents.

      defmodule PostView do
        use JSONAPI.View

        def fields, do: [:id, :text, :body]
        def type, do: "post"
        def relationships do
          [author: UserView,
           comments: CommentView]
        end
      end

      defmodule UserView do
        use JSONAPI.View

        def fields, do: [:id, :username]
        def type, do: "user"
        def relationships, do: []
      end

      defmodule CommentView do
        use JSONAPI.View

        def fields, do: [:id, :text]
        def type, do: "comment"
        def relationships do
          [user: {UserView, :include}]
        end
      end

  You can now call `UserView.show(user, conn, conn.params)` and it will render
  a valid jsonapi doc.

  ## Relationships

  Currently the relationships callback expects that a map is returned
  configuring the information you will need. If you have the following Ecto
  Model setup

      defmodule User do
        schema "users" do
          field :username
          has_many :posts
          has_one :image
        end
      end

  and the includes setup from above. If your Post has loaded the author and the
  query asks for it then it will be loaded.

  So for example:
  `GET /posts?include=post.author` if the author record is loaded on the Post, and you are using
  the `JSONAPI.QueryParser` it will be included in the `includes` section of the JSONAPI document.

  If you always want to include a relationship. First make sure its always preloaded
  and then use the `[user: {UserView, :include}]` syntax in your `includes` function. This tells
  the serializer to *always* include if its loaded.
  """
  defmacro __using__(opts \\ []) do
    {type, opts} = Keyword.pop(opts, :type)
    {namespace, opts} = Keyword.pop(opts, :namespace, "")
    {pluralize, opts} = Keyword.pop(opts, :pluralize, false)
    {trim_null_attrs, _opts} = Keyword.pop(opts, :trim_null_attrs, false)

    quote do
      import JSONAPI.Serializer, only: [serialize: 3]

      @resource_type unquote(type)
      @namespace unquote(namespace)
      @pluralize unquote(pluralize)
      @trim_null_attrs unquote(trim_null_attrs)

      def id(nil), do: nil
      def id(%{__struct__: Ecto.Association.NotLoaded}), do: nil
      def id(%{id: id}), do: to_string(id)

      if @resource_type do
        def type, do: @resource_type
      else
        def type, do: raise "Need to implement type/0"
      end

      if @pluralize do
        def type_url(), do: Inflex.pluralize(type())
      else
        def type_url(), do: type()
      end

      #TODO Figure out the nesting of fields
      if @trim_null_attrs do
        def attributes(data, conn) do
          Map.take(data, fields()) |> Enum.reject(fn({_, v}) -> v == nil end) |> Enum.into(%{})
        end
      else
        def attributes(data, conn) do
          Map.take(data, fields())
        end
      end
      def relationships, do: []
      def fields, do: raise "Need to implement fields/0"

      def show(model, conn, _params),
        do: serialize(__MODULE__, model, conn)
      def index(models, conn, _params),
        do: serialize(__MODULE__, models, conn)

      def url_for(nil, nil) do
        "#{@namespace}/#{type_url()}"
      end

      def url_for(data, nil) when is_list(data) do
        "#{@namespace}/#{type_url()}"
      end

      def url_for(data, nil) do
        "#{@namespace}/#{type_url()}/#{id(data)}"
      end

      def url_for(data, %Plug.Conn{}=conn) when is_list(data) do
        "#{Atom.to_string(conn.scheme)}://#{host_for_conn(conn)}#{@namespace}/#{type_url()}"
      end

      def url_for(data, %Plug.Conn{}=conn) do
        "#{Atom.to_string(conn.scheme)}://#{host_for_conn(conn)}#{@namespace}/#{type_url()}/#{id(data)}"
      end

      def url_for_rel(data, rel_type, conn) do
        "#{url_for(data, conn)}/relationships/#{rel_type}"
      end

      defp host_for_conn(conn) do
        case {conn.scheme, conn.port} do
          {:http, 80} ->
            "#{conn.host}"
          {:http, port} ->
            "#{conn.host}:#{conn.port}"
          {:https, 443} ->
            "#{conn.host}"
          {:https, port} ->
            "#{conn.host}:#{conn.port}"
        end
      end

      if Code.ensure_loaded?(Phoenix) do
        def render("show.json", %{data: data, conn: conn}),
          do: show(data, conn, conn.params)
        def render("show.json", %{data: data, conn: conn, params: params}),
          do: show(data, conn, params)

        def render("index.json", %{data: data, conn: conn}),
          do: index(data, conn, conn.params)
        def render("index.json", %{data: data, conn: conn, params: params}),
          do: show(data, conn, params)
      end

      defoverridable attributes: 2,
                     fields: 0,
                     id: 1,
                     relationships: 0,
                     type: 0,
                     type_url: 0,
                     url_for: 2,
                     url_for_rel: 3
    end
  end
end
