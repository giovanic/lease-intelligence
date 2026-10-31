SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app_current_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.app_current_tenant_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::uuid
$$;


--
-- Name: app_current_user_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.app_current_user_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: counterparties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.counterparties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    kind character varying NOT NULL,
    legal_name character varying NOT NULL,
    trade_name character varying,
    tax_id character varying,
    email character varying,
    phone character varying,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT counterparties_email_lowercase_check CHECK (((email IS NULL) OR ((email)::text = lower((email)::text)))),
    CONSTRAINT counterparties_kind_check CHECK (((kind)::text = ANY ((ARRAY['individual'::character varying, 'company'::character varying])::text[]))),
    CONSTRAINT counterparties_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'archived'::character varying])::text[]))),
    CONSTRAINT counterparties_tax_id_format_check CHECK (((tax_id IS NULL) OR (((kind)::text = 'individual'::text) AND ((tax_id)::text ~ '^[0-9]{11}$'::text)) OR (((kind)::text = 'company'::text) AND ((tax_id)::text ~ '^[0-9]{14}$'::text))))
);

ALTER TABLE ONLY public.counterparties FORCE ROW LEVEL SECURITY;


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    invited_by_id uuid NOT NULL,
    email character varying NOT NULL,
    role character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    token character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    accepted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT invitations_email_lowercase_check CHECK (((email)::text = lower((email)::text))),
    CONSTRAINT invitations_role_check CHECK (((role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'manager'::character varying, 'analyst'::character varying, 'viewer'::character varying])::text[]))),
    CONSTRAINT invitations_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'revoked'::character varying, 'expired'::character varying])::text[])))
);

ALTER TABLE ONLY public.invitations FORCE ROW LEVEL SECURITY;


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    invitation_id uuid,
    role character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    deactivated_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT memberships_role_check CHECK (((role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'manager'::character varying, 'analyst'::character varying, 'viewer'::character varying])::text[]))),
    CONSTRAINT memberships_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'suspended'::character varying])::text[])))
);

ALTER TABLE ONLY public.memberships FORCE ROW LEVEL SECURITY;


--
-- Name: properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.properties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying NOT NULL,
    code character varying,
    property_type character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    street character varying NOT NULL,
    number character varying,
    complement character varying,
    district character varying,
    city character varying NOT NULL,
    state character varying NOT NULL,
    postal_code character varying,
    country_code character varying DEFAULT 'BR'::character varying NOT NULL,
    area_sqm numeric(12,2),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT properties_area_sqm_positive_check CHECK (((area_sqm IS NULL) OR (area_sqm > (0)::numeric))),
    CONSTRAINT properties_country_code_format_check CHECK (((country_code)::text ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT properties_postal_code_format_check CHECK (((postal_code IS NULL) OR ((postal_code)::text ~ '^[0-9]{8}$'::text))),
    CONSTRAINT properties_property_type_check CHECK (((property_type)::text = ANY ((ARRAY['retail'::character varying, 'clinic'::character varying, 'office'::character varying, 'restaurant'::character varying, 'gym'::character varying, 'school'::character varying, 'warehouse'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT properties_state_format_check CHECK (((state)::text ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT properties_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'archived'::character varying])::text[])))
);

ALTER TABLE ONLY public.properties FORCE ROW LEVEL SECURITY;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT tenants_slug_lowercase_check CHECK (((slug)::text = lower((slug)::text))),
    CONSTRAINT tenants_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'suspended'::character varying, 'canceled'::character varying])::text[])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    sign_in_count integer DEFAULT 0 NOT NULL,
    current_sign_in_at timestamp(6) without time zone,
    last_sign_in_at timestamp(6) without time zone,
    current_sign_in_ip character varying,
    last_sign_in_ip character varying,
    full_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: counterparties counterparties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.counterparties
    ADD CONSTRAINT counterparties_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: properties properties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_counterparties_id_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_counterparties_id_tenant_id ON public.counterparties USING btree (id, tenant_id);


--
-- Name: idx_counterparties_unique_tax_id_per_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_counterparties_unique_tax_id_per_tenant ON public.counterparties USING btree (tenant_id, tax_id) WHERE (tax_id IS NOT NULL);


--
-- Name: idx_invitations_id_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_invitations_id_tenant_id ON public.invitations USING btree (id, tenant_id);


--
-- Name: idx_invitations_unique_pending_per_tenant_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_invitations_unique_pending_per_tenant_email ON public.invitations USING btree (tenant_id, email) WHERE ((status)::text = 'pending'::text);


--
-- Name: idx_properties_id_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_properties_id_tenant_id ON public.properties USING btree (id, tenant_id);


--
-- Name: idx_properties_unique_code_per_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_properties_unique_code_per_tenant ON public.properties USING btree (tenant_id, code) WHERE (code IS NOT NULL);


--
-- Name: index_counterparties_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_counterparties_on_tenant_id ON public.counterparties USING btree (tenant_id);


--
-- Name: index_invitations_on_invited_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_invited_by_id ON public.invitations USING btree (invited_by_id);


--
-- Name: index_invitations_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_tenant_id ON public.invitations USING btree (tenant_id);


--
-- Name: index_invitations_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_token ON public.invitations USING btree (token);


--
-- Name: index_memberships_on_invitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_invitation_id ON public.memberships USING btree (invitation_id);


--
-- Name: index_memberships_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_tenant_id ON public.memberships USING btree (tenant_id);


--
-- Name: index_memberships_on_tenant_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_tenant_id_and_user_id ON public.memberships USING btree (tenant_id, user_id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_properties_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_properties_on_tenant_id ON public.properties USING btree (tenant_id);


--
-- Name: index_tenants_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenants_on_slug ON public.tenants USING btree (slug);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: memberships fk_rails_99326fb65d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_99326fb65d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: memberships fk_rails_a959f0d1fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_a959f0d1fb FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: properties fk_rails_d584945dc4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT fk_rails_d584945dc4 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: invitations fk_rails_d799c974a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_d799c974a1 FOREIGN KEY (invited_by_id) REFERENCES public.users(id);


--
-- Name: counterparties fk_rails_f00102f981; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.counterparties
    ADD CONSTRAINT fk_rails_f00102f981 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: invitations fk_rails_f2ab2431e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_f2ab2431e2 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: memberships memberships_invitation_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_invitation_same_tenant FOREIGN KEY (invitation_id, tenant_id) REFERENCES public.invitations(id, tenant_id);


--
-- Name: counterparties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.counterparties ENABLE ROW LEVEL SECURITY;

--
-- Name: counterparties counterparties_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY counterparties_tenant_isolation ON public.counterparties USING ((tenant_id = public.app_current_tenant_id())) WITH CHECK ((tenant_id = public.app_current_tenant_id()));


--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations invitations_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitations_tenant_isolation ON public.invitations USING ((tenant_id = public.app_current_tenant_id())) WITH CHECK ((tenant_id = public.app_current_tenant_id()));


--
-- Name: memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships memberships_self_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_self_visibility ON public.memberships FOR SELECT USING ((user_id = public.app_current_user_id()));


--
-- Name: memberships memberships_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_tenant_isolation ON public.memberships USING ((tenant_id = public.app_current_tenant_id())) WITH CHECK ((tenant_id = public.app_current_tenant_id()));


--
-- Name: properties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;

--
-- Name: properties properties_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY properties_tenant_isolation ON public.properties USING ((tenant_id = public.app_current_tenant_id())) WITH CHECK ((tenant_id = public.app_current_tenant_id()));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261031150001'),
('20261031150000'),
('20261031133227'),
('20261031133226'),
('20261031133225'),
('20261031133222'),
('20261031133221');

