"""LESSON 8 — pytest against the SDK with a mocked transport.

Run:  /usr/bin/python3 -m pytest lattice-lessons/test_lesson08.py -q

What a grader looks for: fixtures instead of copy-paste setup, asserting on
the REQUEST the client actually sent (not just the response), parametrize,
and exception tests with pytest.raises.

EXERCISES (add below, then re-run):
  E1. test that publishing twice with the same entity_id keeps the store at 1.
  E2. parametrize a test over 3 stations asserting each alias name matches
      'ER49-S{station:02d}'.
  E3. test that get_entity on a missing id raises ApiError with .status_code
      == 404 (pytest.raises(...) as excinfo).
  E4. write a fixture 'fleet' that pre-publishes 5 stations and returns the
      fake; use it in a test that asserts 5 distinct entity ids.
Solutions for all four are at the bottom — delete them and rewrite from
memory; that is the drill.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pytest
from anduril.core.api_error import ApiError

import harness
from lesson03_publishing import station_entity_kwargs


@pytest.fixture()
def mock_lattice():
    client, fake = harness.make_client()
    return client, fake


@pytest.fixture()
def first_station():
    return next(harness.stations())


def test_publish_sends_put_to_entities(mock_lattice, first_station):
    client, fake = mock_lattice
    client.entities.publish_entity(**station_entity_kwargs(first_station))
    method, path, body = fake.requests[-1]
    assert (method, path) == ("PUT", "/api/v1/entities")
    assert body["aliases"]["name"] == "ER49-S01"          # wire format is camelCase
    assert body["isLive"] is True


def test_roundtrip_preserves_position(mock_lattice, first_station):
    client, _ = mock_lattice
    sent = station_entity_kwargs(first_station)
    e = client.entities.publish_entity(**sent)
    got = client.entities.get_entity(entity_id=e.entity_id)
    assert got.location.position.latitude_degrees == pytest.approx(first_station["lat"])


# --- SOLUTIONS --------------------------------------------------------------

def test_e1_idempotent_store(mock_lattice, first_station):
    client, fake = mock_lattice
    client.entities.publish_entity(**station_entity_kwargs(first_station))
    client.entities.publish_entity(**station_entity_kwargs(first_station))
    assert len(fake.entities) == 1


@pytest.mark.parametrize("idx", [0, 10, 48])
def test_e2_alias_matches_station(mock_lattice, idx):
    client, _ = mock_lattice
    st = list(harness.stations())[idx]
    e = client.entities.publish_entity(**station_entity_kwargs(st))
    assert e.aliases.name == f"ER49-S{st['station']:02d}"


def test_e3_missing_entity_404(mock_lattice):
    client, _ = mock_lattice
    with pytest.raises(ApiError) as excinfo:
        client.entities.get_entity(entity_id="never-published")
    assert excinfo.value.status_code == 404


@pytest.fixture()
def fleet(mock_lattice):
    client, fake = mock_lattice
    for st in list(harness.stations())[:5]:
        client.entities.publish_entity(**station_entity_kwargs(st))
    return fake


def test_e4_fleet_of_five(fleet):
    assert len(fleet.entities) == 5
    assert len(set(fleet.entities.keys())) == 5
