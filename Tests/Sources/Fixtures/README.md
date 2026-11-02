# Pre-salary store fixture

`PreSalary.sqlite` was generated from pre-salary commit
`e56dea53b88a07dc1b2db20eebee0b7bcdf8ad32`
schema in an isolated temporary checkout on November 2, 2026. It contains
synthetic data only: one hourly job, a $25 hourly rate, an eight-hour shift
worth $200, and completed onboarding.

The migration regression test copies the fixture to a temporary directory,
opens it with the current schema, verifies existing records and relationships,
and saves/reopens the new salary models. Never regenerate this fixture with
the current schema: its purpose is to exercise a released store shape.
