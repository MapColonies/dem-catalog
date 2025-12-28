SET search_path TO public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;


SET search_path TO "DemCatalogManager", public; -- CHANGE SCHEMA NAME TO MATCH ENVIRONMENT
CREATE TYPE product_status AS ENUM ('PUBLISHED', 'UNPUBLISHED'); 
CREATE TYPE product_type AS ENUM ('DTM', 'DSM', 'QuantizedMeshDTM', 'QuantizedMeshDSM', 'Terrain', 'TerrainRGB'); 
CREATE TYPE data_type AS ENUM ('FLOAT64', 'FLOAT32', 'FLOAT16', 'INT64', 'INT32', 'INT16', 'INT8'); 
CREATE TYPE pixel_type AS ENUM ('PUBLISHED', 'UNPUBLISHED'); 
-- Table: records
-- DROP TABLE records;
CREATE TABLE records
(
    identifier text COLLATE pg_catalog."default" NOT NULL,
    product_status product_status NOT NULL DEFAULT 'UNPUBLISHED',
    product_id text COLLATE pg_catalog."default" NOT NULL CHECK (product_id ~* '^[a-zA-Z0-9_-]+$'),
    product_type product_type NOT NULL DEFAULT 'DTM',
    product_name text COLLATE pg_catalog."default",
    product_version numeric NOT NULL CHECK (product_version >= 0) DEFAULT 1,
    producer_name text COLLATE pg_catalog."default" DEFAULT 'IDFMU',
    ingestion_date_utc timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    insert_date_utc timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_date_utc timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    acquisition_time_begin_utc timestamp with time zone NOT NULL,
    acquisition_time_end_utc timestamp with time zone NOT NULL,
    min_resolution_degree numeric NOT NULL,
    max_resolution_degree numeric NOT NULL,
    min_resolution_meter numeric NOT NULL,
    max_resolution_meter numeric NOT NULL,
    min_absolute_accuracy_lep_90 numeric,
    max_absolute_accuracy_lep_90 numeric,
    min_relative_accuracy_lep_90 numeric,
    max_relative_accuracy_lep_90 numeric,
    min_horizontal_accuracy_cep_90 numeric,
    max_horizontal_accuracy_cep_90 numeric,
    geoid_model text COLLATE pg_catalog."default" NOT NULL,
    sensors text COLLATE pg_catalog."default" NOT NULL,
    srs_id text COLLATE pg_catalog."default" NOT NULL,
    srs_name text COLLATE pg_catalog."default" NOT NULL,
    region text COLLATE pg_catalog."default" NOT NULL CHECK (region <> ''),
    data_type data_type NOT NULL,
    no_data_value numeric NOT NULL,
    classification text COLLATE pg_catalog."default" NOT NULL CHECK (classification ~* '^[0-9]$|^[1-9][0-9]$|^(100)$'),
    description text COLLATE pg_catalog."default",
    area_or_point pixel_type NOT NULL,
    footprint_geojson text COLLATE pg_catalog."default" NOT NULL,
    wkt_geometry text COLLATE pg_catalog."default",
    wkb_geometry geometry(Geometry,4326),
    links text COLLATE pg_catalog."default" NOT NULL,
    keywords text COLLATE pg_catalog."default",
    typename text COLLATE pg_catalog."default" NOT NULL,
    schema text COLLATE pg_catalog."default" NOT NULL,
    mdsource text COLLATE pg_catalog."default" NOT NULL,
    xml character varying COLLATE pg_catalog."default" NOT NULL,
    anytext text COLLATE pg_catalog."default" NOT NULL,
    anytext_tsvector tsvector,
    type text COLLATE pg_catalog."default" NOT NULL,
    display_path text COLLATE pg_catalog."default" NOT NULL,
    
    CONSTRAINT records_pkey PRIMARY KEY (identifier),
    CONSTRAINT unique_record_values UNIQUE (product_id, product_type)
);


-- Index: ix_product_id
-- DROP INDEX ix_product_id;
CREATE INDEX ix_product_id
    ON records USING btree
    (product_id COLLATE pg_catalog."default" ASC NULLS LAST);

-- Index: ix_product_name
-- DROP INDEX ix_product_name;
CREATE INDEX ix_product_name
    ON records USING btree
    (product_name COLLATE pg_catalog."default" ASC NULLS LAST);

-- Index: ix_product_type
-- DROP INDEX ix_product_type;
CREATE INDEX ix_product_type ON records (product_type);

-- Index: ix_ingestion_date_utc
-- DROP INDEX ix_ingestion_date_utc;
CREATE INDEX ix_ingestion_date_utc
    ON records USING btree
    (ingestion_date_utc ASC NULLS LAST);

-- Index: ix_acquisition_time_begin_utc
-- DROP INDEX ix_acquisition_time_begin_utc;
CREATE INDEX ix_acquisition_time_begin_utc
    ON records USING btree
    (acquisition_time_begin_utc ASC NULLS LAST);

-- Index: ix_acquisition_time_end_utc
-- DROP INDEX ix_acquisition_time_end_utc;
CREATE INDEX ix_acquisition_time_end_utc
    ON records USING btree
    (acquisition_time_end_utc ASC NULLS LAST);

-- Index: ix_min_resolution_meter
-- DROP INDEX ix_min_resolution_meter;
CREATE INDEX ix_min_resolution_meter
    ON records USING btree
    (min_resolution_meter ASC);    

-- Index: ix_max_resolution_meter
-- DROP INDEX ix_max_resolution_meter;
CREATE INDEX ix_max_resolution_meter
    ON records USING btree
    (max_resolution_meter ASC);

-- Index: records_wkb_geometry_idx
-- DROP INDEX records_wkb_geometry_idx;
CREATE INDEX records_wkb_geometry_idx
    ON records USING gist
    (wkb_geometry);

-- Index: fts_gin_idx
-- DROP INDEX fts_gin_idx;
-- DO NOT CHANGE THIS INDEX NAME --
-- changing its name will disable pycsw full text index
CREATE INDEX fts_gin_idx
    ON records USING gin
    (anytext_tsvector);

-- Trigger function : records_update_anytext
CREATE FUNCTION records_update_anytext() RETURNS trigger
    SET search_path FROM CURRENT
    LANGUAGE plpgsql
    AS $$
BEGIN   
  IF TG_OP = 'INSERT' THEN
    NEW.anytext := CONCAT (
      NEW.product_name,' ',
      NEW.product_version, ' ',
      NEW.product_type, ' ',
      NEW.description, ' ',
      NEW.sensors, ' ',
      NEW.srs_name, ' ',
      NEW.region, ' ',
      NEW.classification, ' ',
      NEW.keywords);
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.anytext := CONCAT (
      COALESCE(NEW.product_name, OLD.product_name),' ',
      COALESCE(NEW.product_version, OLD.product_version), ' ',
      COALESCE(NEW.product_type, OLD.product_type), ' ',
      COALESCE(NEW.description, OLD.description), ' ',
      COALESCE(NEW.sensors, OLD.sensors), ' ',
      COALESCE(NEW.srs_name, OLD.srs_name), ' ',
      COALESCE(NEW.region, OLD.region), ' ',
      COALESCE(NEW.classification, OLD.classification), ' ',
      COALESCE(NEW.keywords, OLD.keywords));
  END IF;
  NEW.anytext_tsvector = to_tsvector('pg_catalog.english', NEW.anytext);
  RETURN NEW;
END;
$$;

-- Trigger: ftsupdate
-- DROP TRIGGER ftsupdate ON records;
CREATE TRIGGER ftsupdate
    BEFORE INSERT OR UPDATE
    ON records
    FOR EACH ROW
    WHEN (NEW.product_name IS NOT NULL 
      OR NEW.product_version IS NOT NULL
      OR NEW.product_type IS NOT NULL
      OR NEW.description IS NOT NULL
      OR NEW.sensors IS NOT NULL
      OR NEW.srs_name IS NOT NULL
      OR NEW.region IS NOT NULL
      OR NEW.classification IS NOT NULL
      OR NEW.keywords IS NOT NULL)
	 EXECUTE PROCEDURE records_update_anytext();

-- Trigger function : records_update_geometry
CREATE FUNCTION records_update_geometry() RETURNS trigger
    SET search_path FROM CURRENT
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.wkt_geometry IS NULL THEN
        RETURN NEW;
    END IF;
    NEW.wkb_geometry := ST_GeomFromText(NEW.wkt_geometry,4326);
    RETURN NEW;
END;
$$;

-- Trigger: records_update_geometry
-- DROP TRIGGER records_update_geometry ON records;
CREATE TRIGGER records_update_geometry
    BEFORE INSERT OR UPDATE
    ON records
    FOR EACH ROW
    EXECUTE PROCEDURE records_update_geometry();

--DROP INDEX product_id_and_type_case_insensitive
CREATE UNIQUE INDEX product_id_and_type_case_insensitive ON records (lower(product_id), product_type);
