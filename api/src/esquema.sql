-- Esquema de la base de datos: Asistencia a Asamblea
-- Se ejecuta automáticamente cada vez que arranca la API (es seguro repetirlo).

CREATE TABLE IF NOT EXISTS administradores (
  id            SERIAL PRIMARY KEY,
  usuario       VARCHAR(50)  NOT NULL UNIQUE,
  nombre        VARCHAR(120) NOT NULL,
  clave_hash    TEXT         NOT NULL,
  creado_en     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS locales (
  id                        SERIAL PRIMARY KEY,
  numero                    VARCHAR(20)   NOT NULL UNIQUE,
  coeficiente               NUMERIC(10,6) NOT NULL CHECK (coeficiente >= 0),
  propietario_nombre        VARCHAR(150)  NOT NULL,
  propietario_cedula        VARCHAR(20)   NOT NULL,
  apoderado_nombre          VARCHAR(150),
  apoderado_cedula          VARCHAR(20),
  apoderado_registrado_por  VARCHAR(20)   CHECK (apoderado_registrado_por IN ('administradora', 'apoderado')),
  activo                    BOOLEAN       NOT NULL DEFAULT TRUE,
  actualizado_en            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asambleas (
  id          SERIAL PRIMARY KEY,
  nombre      VARCHAR(150) NOT NULL,
  fecha       DATE         NOT NULL DEFAULT CURRENT_DATE,
  estado      VARCHAR(10)  NOT NULL DEFAULT 'creada' CHECK (estado IN ('creada', 'abierta', 'cerrada')),
  abierta_en  TIMESTAMPTZ,
  cerrada_en  TIMESTAMPTZ,
  creado_en   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Solo puede haber una asamblea abierta a la vez.
CREATE UNIQUE INDEX IF NOT EXISTS asambleas_una_abierta ON asambleas ((estado)) WHERE estado = 'abierta';

CREATE TABLE IF NOT EXISTS asistencias (
  id                SERIAL PRIMARY KEY,
  asamblea_id       INT           NOT NULL REFERENCES asambleas(id) ON DELETE CASCADE,
  local_id          INT           NOT NULL REFERENCES locales(id),
  tipo              VARCHAR(12)   NOT NULL CHECK (tipo IN ('propietario', 'apoderado')),
  asistente_nombre  VARCHAR(150)  NOT NULL,
  asistente_cedula  VARCHAR(20)   NOT NULL,
  coeficiente       NUMERIC(10,6) NOT NULL,
  registrado_por    VARCHAR(20)   NOT NULL DEFAULT 'asistente' CHECK (registrado_por IN ('asistente', 'administradora')),
  hora_ingreso      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  UNIQUE (asamblea_id, local_id)
);

CREATE INDEX IF NOT EXISTS asistencias_asamblea ON asistencias (asamblea_id);
