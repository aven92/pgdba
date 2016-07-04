CREATE OR REPLACE FUNCTION url_decode(encode_url text)
RETURNS text
IMMUTABLE STRICT AS $$
DECLARE
	bin bytea = '';
	byte text;
BEGIN
	FOR byte IN (select (regexp_matches(encode_url, '(%..|.)', 'g'))[1]) LOOP
		IF length(byte) = 3 THEN
			bin = bin || decode(substring(byte, 2, 2), 'hex');
		ELSE
			bin = bin || byte::bytea;
		END IF;
	END LOOP;
RETURN convert_from(bin, 'utf8');
END
$$
LANGUAGE plpgsql;	


CREATE OR REPLACE FUNCTION decode_url(encode_url character varying)
RETURNS character varying
IMMUTABLE STRICT AS $$
	select convert_from(CasT(E'\\x' || string_agg(CasE WHEN length(r.m[1]) = 1 THEN encode(convert_to(r.m[1], 'SQL_asCII'), 'hex') ELSE substring(r.m[1] from 2 for 2) END, '') as bytea), 'UTF8')
	from regexp_matches($1, '%[0-9a-f][0-9a-f]|.', 'gi') as r(m);
$$
LANGUAGE SQL;
