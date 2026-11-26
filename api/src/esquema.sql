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

-- Rol de cada cuenta: la administradora o la persona de logística (votaciones).
ALTER TABLE administradores ADD COLUMN IF NOT EXISTS rol VARCHAR(20) NOT NULL DEFAULT 'administradora';

-- Votaciones: preguntas de una asamblea y el voto de cada local.
CREATE TABLE IF NOT EXISTS preguntas (
  id          SERIAL PRIMARY KEY,
  asamblea_id INT          NOT NULL REFERENCES asambleas(id) ON DELETE CASCADE,
  numero      INT          NOT NULL,
  texto       TEXT         NOT NULL,
  opciones    JSONB        NOT NULL,
  estado      VARCHAR(10)  NOT NULL DEFAULT 'creada' CHECK (estado IN ('creada', 'abierta', 'cerrada')),
  abierta_en  TIMESTAMPTZ,
  cerrada_en  TIMESTAMPTZ,
  creado_en   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Solo una pregunta abierta a la vez.
CREATE UNIQUE INDEX IF NOT EXISTS preguntas_una_abierta ON preguntas ((estado)) WHERE estado = 'abierta';

CREATE TABLE IF NOT EXISTS votos (
  id              SERIAL PRIMARY KEY,
  pregunta_id     INT           NOT NULL REFERENCES preguntas(id) ON DELETE CASCADE,
  local_id        INT           NOT NULL REFERENCES locales(id),
  opcion          INT           NOT NULL,
  coeficiente     NUMERIC(10,6) NOT NULL,
  tipo            VARCHAR(12)   NOT NULL,
  votante_nombre  VARCHAR(150)  NOT NULL,
  votante_cedula  VARCHAR(20)   NOT NULL,
  registrado_por  VARCHAR(20)   NOT NULL DEFAULT 'asistente',
  hora            TIMESTAMPTZ   NOT NULL DEFAULT now(),
  UNIQUE (pregunta_id, local_id)
);

CREATE INDEX IF NOT EXISTS votos_pregunta ON votos (pregunta_id);
