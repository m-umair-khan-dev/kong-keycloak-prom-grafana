-- Create database and user for Kong
CREATE USER kong WITH PASSWORD 'kongpass';
CREATE DATABASE kong OWNER kong;
GRANT ALL PRIVILEGES ON DATABASE kong TO kong;

-- Create database and user for Keycloak
CREATE USER keycloak WITH PASSWORD 'keycloakpass';
CREATE DATABASE keycloak OWNER keycloak;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
