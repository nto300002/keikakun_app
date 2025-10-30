```sql
-- m9n8x7y6z5a4 アセスメントスキーマ
-- ENUM
CREATE TYPE household AS ENUM ('same', 'separate');


CREATE TYPE medical_care_insurance AS ENUM (
    'national_health_insurance', 'mutual_aid', 'social_insurance',
    'livelihood_protection', 'other'
);


CREATE TYPE aiding_type AS ENUM ('none', 'subsidized', 'full_exemption');


CREATE TYPE work_conditions AS ENUM (
    'general_employment', 'part_time', 'transition_support',
    'continuous_support_a', 'continuous_support_b', 'main_employment', 'other'
);


CREATE TYPE work_outside_facility AS ENUM ('hope', 'not_hope', 'undecided');


-- TABLE
CREATE TABLE family_of_service_recipients (
    id SERIAL PRIMARY KEY,
    welfare_recipient_id UUID NOT NULL,
    name TEXT NOT NULL,
    relationship TEXT NOT NULL,
    household household NOT NULL,
    ones_health TEXT NOT NULL,
    remarks TEXT,
    family_structure_chart TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
);

CREATE TRIGGER update_family_of_service_recipients_updated_at
BEFORE UPDATE ON family_of_service_recipients
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();



CREATE TABLE welfare_services_used (
    id SERIAL PRIMARY KEY,
    welfare_recipient_id UUID NOT NULL,
    office_name TEXT NOT NULL,
    starting_day DATE NOT NULL,
    amount_used TEXT NOT NULL,
    service_name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
);

CREATE TRIGGER update_welfare_services_used_updated_at
BEFORE UPDATE ON welfare_services_used
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();



CREATE TABLE medical_matters (
    id SERIAL PRIMARY KEY,
    welfare_recipient_id UUID NOT NULL UNIQUE,
    medical_care_insurance medical_care_insurance NOT NULL,
    medical_care_insurance_other_text TEXT,
    aiding aiding_type NOT NULL,
    history_of_hospitalization_in_the_past_2_years BOOLEAN NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE
);

CREATE TRIGGER update_medical_matters_updated_at
BEFORE UPDATE ON medical_matters
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();



CREATE TABLE history_of_hospital_visits (
    id SERIAL PRIMARY KEY,
    medical_matters_id INTEGER NOT NULL,
    disease TEXT NOT NULL,
    frequency_of_hospital_visits TEXT NOT NULL,
    symptoms TEXT NOT NULL,
    medical_institution TEXT NOT NULL,
    doctor TEXT NOT NULL,
    tel TEXT NOT NULL,
    taking_medicine BOOLEAN NOT NULL,
    date_started DATE,
    date_ended DATE,
    special_remarks TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    FOREIGN KEY (medical_matters_id) REFERENCES medical_matters(id) ON DELETE CASCADE
);

CREATE TRIGGER update_history_of_hospital_visits_updated_at
BEFORE UPDATE ON history_of_hospital_visits
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();


CREATE TABLE employment_related (
    id SERIAL PRIMARY KEY,
    welfare_recipient_id UUID NOT NULL UNIQUE,
    created_by_staff_id UUID NOT NULL,
    work_conditions work_conditions NOT NULL,
    regular_or_part_time_job BOOLEAN NOT NULL,
    employment_support BOOLEAN NOT NULL,
    work_experience_in_the_past_year BOOLEAN NOT NULL,
    suspension_of_work BOOLEAN NOT NULL,
    qualifications TEXT,
    main_places_of_employment TEXT,
    general_employment_request BOOLEAN NOT NULL,
    desired_job TEXT,
    special_remarks TEXT,
    work_outside_the_facility work_outside_facility NOT NULL,
    special_note_about_working_outside_the_facility TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by_staff_id) REFERENCES staffs(id) ON DELETE CASCADE
);

CREATE TRIGGER update_employment_related_updated_at
BEFORE UPDATE ON employment_related
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();


CREATE TABLE issue_analyses (
    id SERIAL PRIMARY KEY,
    welfare_recipient_id UUID NOT NULL UNIQUE,
    created_by_staff_id UUID NOT NULL,
    what_i_like_to_do TEXT,
    im_not_good_at TEXT,
    the_life_i_want TEXT,
    the_support_i_want TEXT,
    points_to_keep_in_mind_when_providing_support TEXT,
    future_dreams TEXT,
    other TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    FOREIGN KEY (welfare_recipient_id) REFERENCES welfare_recipients(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by_staff_id) REFERENCES staffs(id) ON DELETE CASCADE
);

CREATE TRIGGER update_issue_analyses_updated_at
BEFORE UPDATE ON issue_analyses
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- DROP DOWN
DROP TABLE IF EXISTS issue_analyses;
DROP TABLE IF EXISTS employment_related;
DROP TABLE IF EXISTS history_of_hospital_visits;
DROP TABLE IF EXISTS medical_matters;
DROP TABLE IF EXISTS welfare_services_used;
DROP TABLE IF EXISTS family_of_service_recipients;

DROP TYPE IF EXISTS work_outside_facility;
DROP TYPE IF EXISTS work_conditions;
DROP TYPE IF EXISTS aiding_type;
DROP TYPE IF EXISTS medical_care_insurance;
DROP TYPE IF EXISTS household;
```
