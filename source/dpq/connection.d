module dpq.connection;

import derelict.pq.pq;

import dpq.exception;
import dpq.result;
import dpq.value;
import dpq.attributes;

import std.string;
import derelict.pq.pq;
import std.conv : to;
import std.traits;

struct Connection
{
	private PGconn* _connection;

	this(string connString)
	{
		char* err;
		auto opts = PQconninfoParse(cast(char*)connString.toStringz, &err);

		if (err != null)
		{
			throw new DPQException(err.fromStringz.to!string);
		}

		_connection = PQconnectdb(connString.toStringz);
		_dpqLastConnection = &this;
	}

	@disable this(this);

	~this()
	{
		PQfinish(_connection);
	}

	void close()
	{
		PQfinish(_connection);
		_connection = null;
	}

	@property const(string) db()
	{
		return PQdb(_connection).to!string;
	}

	@property const(string) user()
	{
		return PQuser(_connection).to!string;
	}

	@property const(string) password()
	{
		return PQpass(_connection).to!string;
	}

	@property const(string) host()
	{
		return PQhost(_connection).to!string;
	}
	@property const(string) port()
	{
		return PQport(_connection).to!string;
	}

	Result exec(string command)
	{
		PGresult* res = PQexec(_connection, cast(const char*)command.toStringz);
		return Result(res);
	}

	Result execParams(T...)(string command, T params)
	{
		Value[] values;
		foreach(param; params)
			values ~= Value(param);

		return execParams(command, values);
	}

	Result execParams(string command, Value[] params)
	{
		const char* cStr = cast(const char*) command.toStringz;

		auto pTypes = params.paramTypes;
		auto pValues = params.paramValues;
		auto pLengths = params.paramLengths;
		auto pFormats = params.paramFormats;

		auto res = PQexecParams(
				_connection, 
				cStr, 
				params.length.to!int, 
				pTypes.ptr, 
				pValues.ptr,
				pLengths.ptr,
				pFormats.ptr,
				1);

		return Result(res);
	}

	@property string errorMessage()
	{
		return PQerrorMessage(_connection).to!string;
	}

	void ensureSchema(T...)()
	{
		import std.stdio;
		foreach (type; T)
		{
			enum name = relationName!(type);
			string str = "CREATE TABLE IF NOT EXISTS \"" ~ name ~ "\" (%s)";

			string cols;
			foreach(m; __traits(allMembers, type))
			{
				cols ~= "\"" ~ attributeName!(mixin("type." ~ m)) ~ "\"";

				alias t = typeof(mixin("type." ~ m));
				writeln("Type: ", typeid(t));

				cols ~= " ";

				// TODO: More types, embedded structs, Date types

				// Basic data types
				static if (hasUDA!(mixin("type." ~ m), PGTypeAttribute))
					cols ~= getUDAs!(mixin("type." ~ m), PGTypeAttribute)[0].type;
				else
				{
					alias tu = Unqual!(typeof(mixin("type." ~ m)));

					static if (is(tu == int))
						cols ~= "INT";
					else static if (is(tu == long))
						cols ~= "BIGINT";
					else static if (is(tu == float))
						cols ~= "FLOAT4";
					else static if (is(tu == double))
						cols ~= "FLOAT8";
					else static if (is(tu == char[]) || is(tu == string))
						cols ~= "TEXT";
					else static if (is(tu == bool))
						cols ~= "BOOL";
					else static if (is(tu == char))
						cols ~= "CHAR(1)";
					else static if(is(tu == ubyte[]) || is(tu == byte[]))
						cols ~= "BYTEA";
					// Default to bytea because we fetch and send everything in binary anyway
					else
						static assert(false, "Cannot map type \"" ~ t.stringof ~ "\" of field " ~ m ~ " to any PG type, please specify it manually using @type.");
				}
				


				static if (hasUDA!(mixin("type." ~ m), PrimaryKeyAttribute))
					cols ~= " PRIMARY KEY";


				cols ~= ", ";
			}

			cols = cols[0 .. $ - 2];
			str = str.format(cols);




			std.stdio.writeln(str);
			//exec(str);
		}
	}

	Nullable!T find(T, U)(U id)
	{
		return find!T(primaryKeyName!T, id);
	}

	Nullable!T find(T, U)(string col, U val)
	{
		import dpq.querybuilder;
		import std.stdio;

		string[] members;
		foreach (m; serialisableMembers!T)
			members ~= attributeName!(mixin("T." ~ m));

		QueryBuilder qb;
		qb.select(members)
			.from(relationName!T)
			.where(col ~ " = {col_" ~ col ~ "}");

		qb["col_" ~ col] = val;

		auto q = qb.query(this);

		auto r = q.run();
		if (r.rows == 0)
			return Nullable!T.init;

		//return T();
		
		T res;
		foreach (m; serialisableMembers!T)
		{
			enum n = attributeName!(mixin("T." ~ m));
			try
			{
				mixin("res." ~ m) = r[0][n].as!(typeof(mixin("res." ~ m)));
			}
			catch {}
		}
		return Nullable!T(res);
	}
}

package Connection* _dpqLastConnection;

shared static this()
{
	DerelictPQ.load();
}
