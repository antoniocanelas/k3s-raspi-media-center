from pathlib import Path


def test_sonarr_config_mount_uses_sonarr_subpath():
    deployment = Path("base/sonarr/deployment.yaml").read_text()

    assert "subPath: sonarr" in deployment
    assert "subPath: jellyfin" not in deployment
