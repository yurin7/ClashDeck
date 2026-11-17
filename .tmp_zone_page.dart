    final scheme = Theme.of(context).colorScheme;
    SliverPersistentHeader zoneHeader(bool open, VoidCallback onToggle,
            VoidCallback? onAdd) =>
        SliverPersistentHeader(
          pinned: true,
          delegate: _ZoneHeaderDelegate(
            background: scheme.surface,
            child: _buildZoneHeader(
              context,
              title: title,
              subtitle: subtitle,
              rules: rules,
              zone: zone,
              open: open,
              onToggle: onToggle,
              onAdd: onAdd,
            ),
          ),
        );

    return CustomScrollView(
      slivers: [
        zoneHeader(
          _localOpen,
          () => setState(() => _localOpen = !_localOpen),
          () => _editRule(),
        ),
        if (_localOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              rules: local,
              zone: RuleZone.local,
              onlineOpen: false,
              terminalLate: terminalLate,
            ),
          ),
        SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        zoneHeader(
          _onlineOpen,
          () => setState(() => _onlineOpen = !_onlineOpen),
          _importRules,
        ),
        if (_onlineOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              rules: online,
              zone: RuleZone.online,
              onlineOpen: true,
              terminalLate: terminalLate,
            ),
          ),
        SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        zoneHeader(
          _geoOpen,
          () => setState(() => _geoOpen = !_geoOpen),
          _addGeoRule,
        ),
        if (_geoOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              rules: geo,
              zone: RuleZone.geo,
              onlineOpen: false,
              terminalLate: terminalLate,
            ),
          ),
        SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        zoneHeader(
          _terminalOpen,
          () => setState(() => _terminalOpen = !_terminalOpen),
          null,
        ),
        if (_terminalOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              rules: terminal,
              zone: RuleZone.terminal,
              onlineOpen: false,
              terminalLate: terminalLate,
            ),
          ),
      ],
    );
