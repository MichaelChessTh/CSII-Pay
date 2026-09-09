import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:csii_pay_app/ui/core/theme.dart';
import 'package:csii_pay_app/ui/core/widgets/common_widgets.dart';
import 'package:csii_pay_app/domain/models/marketplace_application.dart';
import 'package:csii_pay_app/ui/features/home/view_models/wallet_view_model.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MarketplaceApplication> _allJobs = [];
  bool _isLoading = false;

  // Filter state
  bool _showFilters = false;
  String _selectedType = 'all'; // 'all', 'student application', 'faculty application'
  String _selectedCategory = 'all';
  int? _selectedDifficulty; // null or 1..5
  String _sortBy = 'newest'; // 'newest', 'wage_high', 'wage_low'

  bool get _hasActiveFilters =>
      _selectedType != 'all' ||
      _selectedCategory != 'all' ||
      _selectedDifficulty != null;

  static const List<String> _categories = [
    'social relations',
    'business',
    'programming',
    'design',
    'pitching',
    'tech',
    'personal',
  ];

  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadJobs();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _loadJobs(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    final vm = context.read<WalletViewModel>();
    try {
      final jobs = await vm.marketplaceService.fetchApplications(
        currentAccountId: vm.currentAccountId,
      );
      if (mounted) {
        setState(() {
          _allJobs = jobs;
          if (!silent) _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  List<MarketplaceApplication> get _filteredExploreJobs {
    return _allJobs.where((j) {
      // Hide completed jobs from the public market feed
      if (!j.isOpen) return false;
      if (_selectedType != 'all' && j.type.toLowerCase() != _selectedType.toLowerCase()) {
        return false;
      }
      if (_selectedCategory != 'all' && j.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      if (_selectedDifficulty != null && j.difficulty != _selectedDifficulty) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        if (_sortBy == 'wage_high') return b.wage.compareTo(a.wage);
        if (_sortBy == 'wage_low') return a.wage.compareTo(b.wage);
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  List<MarketplaceApplication> get _myApplications {
    final vm = context.read<WalletViewModel>();
    final myId = vm.currentAccountId;
    return _allJobs.where((j) => j.creatorAccountId == myId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Marketplace',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'P2P Decentralized Campus Jobs & Escrow',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: _loadJobs,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.brandPurple,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Browse Applications'),
            Tab(text: 'My Applications'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExploreTab(),
          _buildMyJobsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brandPurple,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Post Application',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        onPressed: () => _openCreateJobModal(context),
      ),
    );
  }

  Widget _buildExploreTab() {
    final jobs = _filteredExploreJobs;
    return RefreshIndicator(
      onRefresh: _loadJobs,
      color: AppColors.brandPurple,
      backgroundColor: AppColors.bgCard,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildFilterBar()),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brandPurple),
              ),
            )
          else if (jobs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded, size: 56, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'No applications match your filters',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedType = 'all';
                          _selectedCategory = 'all';
                          _selectedDifficulty = null;
                        });
                      },
                      child: Text('Reset Filters', style: GoogleFonts.outfit(color: AppColors.brandCyan)),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final job = jobs[index];
                    return _JobCard(
                      job: job,
                      onTap: () => _openJobDetailsModal(job),
                    );
                  },
                  childCount: jobs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyJobsTab() {
    final jobs = _myApplications;
    return RefreshIndicator(
      onRefresh: _loadJobs,
      color: AppColors.brandPurple,
      backgroundColor: AppColors.bgCard,
      child: jobs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_outlined, size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'You haven\'t posted any applications yet',
                    style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPurple),
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: Text('Create Application', style: GoogleFonts.outfit(color: Colors.white)),
                    onPressed: () => _openCreateJobModal(context),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                return _MyJobCard(
                  job: job,
                  onTap: () => _openJobDetailsModal(job),
                );
              },
            ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: AppColors.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter toggle & Sort header bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _showFilters = !_showFilters),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _hasActiveFilters
                          ? AppColors.brandPurple.withValues(alpha: 0.2)
                          : AppColors.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _hasActiveFilters
                            ? AppColors.brandPurple
                            : AppColors.glassStroke,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: _hasActiveFilters
                              ? AppColors.brandPurple
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showFilters ? 'Hide Filters' : 'Filters',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _hasActiveFilters
                                ? AppColors.brandPurple
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (_hasActiveFilters) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.brandPurple,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Active',
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(
                          _showFilters
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedType = 'all';
                        _selectedCategory = 'all';
                        _selectedDifficulty = null;
                      });
                    },
                    child: Text(
                      'Clear',
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.brandCyan),
                    ),
                  ),
                ],
                const Spacer(),
                // Sort Dropdown
                PopupMenuButton<String>(
                  color: AppColors.bgCard,
                  initialValue: _sortBy,
                  onSelected: (v) => setState(() => _sortBy = v),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'newest', child: Text('Newest First')),
                    const PopupMenuItem(value: 'wage_high', child: Text('Highest Wage')),
                    const PopupMenuItem(value: 'wage_low', child: Text('Lowest Wage')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassStroke),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort_rounded, size: 15, color: AppColors.brandCyan),
                        const SizedBox(width: 4),
                        Text(
                          _sortBy == 'newest'
                              ? 'Newest'
                              : (_sortBy == 'wage_high' ? 'Wage: High' : 'Wage: Low'),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Collapsible filter content
          if (_showFilters) ...[
            const SizedBox(height: 10),
            // Type filter
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip(
                    label: 'All Types',
                    selected: _selectedType == 'all',
                    onSelected: () => setState(() => _selectedType = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Student Application',
                    selected: _selectedType == 'student application',
                    onSelected: () => setState(() => _selectedType = 'student application'),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Team Application',
                    selected: _selectedType == 'team application',
                    onSelected: () => setState(() => _selectedType = 'team application'),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Faculty Application',
                    selected: _selectedType == 'faculty application',
                    onSelected: () => setState(() => _selectedType = 'faculty application'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Category chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildCategoryChip('all', 'All Categories'),
                  ..._categories.map((c) => _buildCategoryChip(c, _formatCategory(c))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Difficulty row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Difficulty:',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  for (int d = 1; d <= 5; d++)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDifficulty = (_selectedDifficulty == d) ? null : d;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _selectedDifficulty == d
                              ? AppColors.brandGold.withValues(alpha: 0.25)
                              : AppColors.bgCard,
                          border: Border.all(
                            color: _selectedDifficulty == d
                                ? AppColors.brandGold
                                : AppColors.glassStroke,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$d★',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _selectedDifficulty == d
                                ? AppColors.brandGold
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandPurple.withValues(alpha: 0.3) : AppColors.bgCard,
          border: Border.all(
            color: selected ? AppColors.brandPurple : AppColors.glassStroke,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String raw, String display) {
    final selected = _selectedCategory == raw;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = raw),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandCyan.withValues(alpha: 0.2) : AppColors.bgCard,
            border: Border.all(
              color: selected ? AppColors.brandCyan : AppColors.glassStroke,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            display,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.brandCyan : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  String _formatCategory(String c) {
    return c
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  void _openCreateJobModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateApplicationModal(
        onCreated: (newJob) {
          setState(() {
            _allJobs.insert(0, newJob);
          });
        },
      ),
    );
  }

  Future<void> _openJobDetailsModal(MarketplaceApplication job) async {
    final claimed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _JobDetailsModal(
        job: job,
        onClaimSuccess: () {
          _loadJobs();
        },
      ),
    );

    if (claimed == true) {
      if (!mounted) return;
      _loadJobs();
      _showCongratulationsDialog(job);
    }
  }

  void _showCongratulationsDialog(MarketplaceApplication job) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.brandGold, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.celebration_rounded, color: AppColors.brandGold, size: 28),
            const SizedBox(width: 10),
            Text(
              'Congratulations!',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You successfully completed this application and claimed your reward!',
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brandGold.withValues(alpha: 0.2),
                    AppColors.success.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Text(
                    'Reward Received',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandGold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+${job.wage.toStringAsFixed(job.wage.truncateToDouble() == job.wage ? 0 : 2)} ${job.wageToken}',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Great!',
              style: GoogleFonts.outfit(
                color: AppColors.brandCyan,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JOB CARD (EXPLORE TAB)
// ─────────────────────────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onTap});
  final MarketplaceApplication job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOpen = job.isOpen;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.brandPurple.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                job.category.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brandPurple,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Builder(
                              builder: (_) {
                                final isTeam = job.type == 'team application' ||
                                    job.creatorAccountId.startsWith('Team:') ||
                                    (job.creatorNickname?.startsWith('Team:') ?? false);
                                final isFaculty = job.type == 'faculty application';
                                final label = isTeam ? 'TEAM' : (isFaculty ? 'FACULTY' : 'STUDENT');
                                final color = isTeam
                                    ? const Color(0xFF10B981)
                                    : (isFaculty ? AppColors.brandPurple : AppColors.brandCyan);
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: isTeam ? Border.all(color: color.withValues(alpha: 0.3)) : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isTeam) ...[
                                        Icon(Icons.groups_rounded, size: 11, color: color),
                                        const SizedBox(width: 3),
                                      ],
                                      Text(
                                        label,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Wage Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isOpen
                            ? [const Color(0xFF6366F1), const Color(0xFF8B5CF6)]
                            : [AppColors.textMuted, AppColors.bgCard],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isOpen
                          ? [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${job.wage.toStringAsFixed(job.wage.truncateToDouble() == job.wage ? 0 : 2)} ${job.wageToken}',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          isOpen ? 'ESCROW LOCKED' : 'COMPLETED',
                          style: GoogleFonts.outfit(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                job.description,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Divider(color: AppColors.glassStroke.withValues(alpha: 0.5), height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    job.deadline.isNotEmpty ? 'Due: ${job.deadline}' : 'No deadline',
                    style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  // Difficulty stars
                  Row(
                    children: [
                      for (int i = 1; i <= 5; i++)
                        Icon(
                          i <= job.difficulty ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 14,
                          color: i <= job.difficulty ? AppColors.brandGold : AppColors.textMuted,
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'by @${job.creatorAccountId}',
                    style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY JOB CARD (WITH REVEALABLE SECRET CODE)
// ─────────────────────────────────────────────────────────────────────────────
class _MyJobCard extends StatefulWidget {
  const _MyJobCard({required this.job, required this.onTap});
  final MarketplaceApplication job;
  final VoidCallback onTap;

  @override
  State<_MyJobCard> createState() => _MyJobCardState();
}

class _MyJobCardState extends State<_MyJobCard> {
  bool _revealSecret = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final secret = job.secretCode ?? '••••••';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (job.type == 'team application' ||
                    job.creatorAccountId.startsWith('Team:') ||
                    (job.creatorNickname?.startsWith('Team:') ?? false)) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.groups_rounded, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          'TEAM',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: job.isOpen
                        ? AppColors.brandCyan.withValues(alpha: 0.15)
                        : AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    job.status,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: job.isOpen ? AppColors.brandCyan : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Wage: ${job.wage} ${job.wageToken} (Deposited into Smart Contract)',
              style: GoogleFonts.outfit(fontSize: 13, color: AppColors.brandGold),
            ),
            const SizedBox(height: 12),
            if (job.isOpen) ...[
              // Secret Code Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassStroke),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, size: 20, color: AppColors.brandCyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unique 6-Digit Release Code:',
                            style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textSecondary),
                          ),
                          Text(
                            _revealSecret ? secret : '••••••',
                            style: GoogleFonts.robotoMono(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4,
                              color: AppColors.brandCyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _revealSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _revealSecret = !_revealSecret),
                    ),
                    if (job.secretCode != null)
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textSecondary),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: job.secretCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Secret code copied: ${job.secretCode}'),
                              backgroundColor: AppColors.brandPurple,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Give this 6-digit code to the person doing the job once they complete the work so they can unlock their payment.',
                style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Application Completed',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                          Text(
                            'Worker claimed escrow payout. Release code redeemed and deactivated.',
                            style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATE APPLICATION MODAL
// ─────────────────────────────────────────────────────────────────────────────
class _CreateApplicationModal extends StatefulWidget {
  const _CreateApplicationModal({required this.onCreated});
  final void Function(MarketplaceApplication) onCreated;

  @override
  State<_CreateApplicationModal> createState() => _CreateApplicationModalState();
}

class _CreateApplicationModalState extends State<_CreateApplicationModal> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _lineIdCtrl = TextEditingController();
  final _wageCtrl = TextEditingController();
  final _deadlineCtrl = TextEditingController();

  final String _type = 'student application';
  String? _selectedTeam; // null = Personal, non-null = team name
  String _category = 'tech';
  int _difficulty = 3;
  String _wageToken = 'CSP';
  bool _submitting = false;
  String? _errorMessage;

  static const List<String> _categories = [
    'social relations',
    'business',
    'programming',
    'design',
    'pitching',
    'tech',
    'personal',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletViewModel>().loadMyGroups();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _lineIdCtrl.dispose();
    _wageCtrl.dispose();
    _deadlineCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final lineId = _lineIdCtrl.text.trim();
    final wageStr = _wageCtrl.text.trim();
    final deadline = _deadlineCtrl.text.trim();

    if (title.isEmpty || desc.isEmpty || lineId.isEmpty || wageStr.isEmpty) {
      setState(() => _errorMessage = 'Please fill out all required fields.');
      return;
    }

    final wage = double.tryParse(wageStr);
    if (wage == null || wage <= 0) {
      setState(() => _errorMessage = 'Please enter a valid positive wage.');
      return;
    }

    final vm = context.read<WalletViewModel>();
    final isTeam = _selectedTeam != null;
    final teamData = isTeam
        ? vm.myGroups.firstWhere(
            (g) => g['name'] == _selectedTeam,
            orElse: () => <String, dynamic>{},
          )
        : null;

    final myBalance = isTeam
        ? ((teamData?['balance'] as num?)?.toDouble() ?? 0.0)
        : (_wageToken == 'CSP'
            ? (vm.account?.balances.csp ?? 0.0)
            : (vm.account?.balances.bdp ?? 0.0));

    final effectiveToken = isTeam ? 'CSP' : _wageToken;

    if (myBalance < wage) {
      setState(() => _errorMessage =
          'Insufficient $effectiveToken balance in ${isTeam ? "Team $_selectedTeam" : "Personal Wallet"}. Required: $wage, Available: $myBalance');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final res = await vm.marketplaceService.createApplication(
      creatorAccountId: vm.currentAccountId!,
      creatorNickname: vm.currentProfile?.nickname ?? vm.currentAccountId,
      title: title,
      type: isTeam ? 'team application' : _type,
      category: _category,
      description: desc,
      deadline: deadline.isEmpty ? 'Flexible' : deadline,
      difficulty: _difficulty,
      lineId: lineId,
      wage: wage,
      wageToken: effectiveToken,
      teamName: _selectedTeam,
    );

    setState(() => _submitting = false);

    if (res.success && res.data != null) {
      widget.onCreated(res.data!);
      if (mounted) {
        Navigator.pop(context);
        _showSuccessDialog(context, res.data!);
      }
    } else {
      setState(() => _errorMessage = res.error ?? 'Failed to create application');
    }
  }

  void _showSuccessDialog(BuildContext context, MarketplaceApplication job) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
            const SizedBox(width: 8),
            Text('Application Created!', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${job.wage} ${job.wageToken} has been deposited into the escrow smart contract.',
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              'Unique 6-Digit Secret Code:',
              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bgDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandCyan),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    job.secretCode ?? '',
                    style: GoogleFonts.robotoMono(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: AppColors.brandCyan,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: AppColors.brandCyan),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: job.secretCode ?? ''));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Secret code copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Keep this code secret until the worker finishes the task. You can always review it in your "My Applications" tab.',
              style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Done', style: GoogleFonts.outfit(color: AppColors.brandPurple)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();
    final isTeam = _selectedTeam != null;
    final teamData = isTeam
        ? vm.myGroups.firstWhere(
            (g) => g['name'] == _selectedTeam,
            orElse: () => <String, dynamic>{},
          )
        : null;

    final balance = isTeam
        ? ((teamData?['balance'] as num?)?.toDouble() ?? 0.0)
        : (_wageToken == 'CSP'
            ? (vm.account?.balances.csp ?? 0.0)
            : (vm.account?.balances.bdp ?? 0.0));

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.paddingOf(context).bottom +
              24,
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassStroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Create Job Application',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Funds are escrowed until the worker supplies the secret code',
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),

            // Wallet / Funder Selector
            Text(
              'Post as & Pay From:',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text('Personal (${(vm.account?.balances.csp ?? 0.0).toStringAsFixed(1)} CSP)'),
                    selected: _selectedTeam == null,
                    selectedColor: AppColors.brandCyan.withValues(alpha: 0.3),
                    backgroundColor: AppColors.bgCard,
                    labelStyle: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedTeam == null ? Colors.white : AppColors.textSecondary,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _selectedTeam = null);
                    },
                  ),
                  ...vm.myGroups.map((g) {
                    final gname = g['name']?.toString() ?? '';
                    final gbal = (g['balance'] as num?)?.toDouble() ?? 0.0;
                    final isSel = _selectedTeam == gname;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        avatar: const Icon(Icons.groups_rounded, size: 16),
                        label: Text('$gname (${gbal.toStringAsFixed(1)} CSP)'),
                        selected: isSel,
                        selectedColor: AppColors.brandGold.withValues(alpha: 0.35),
                        backgroundColor: AppColors.bgCard,
                        labelStyle: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : AppColors.textSecondary,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() {
                              _selectedTeam = gname;
                              _wageToken = 'CSP';
                            });
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            if (_selectedTeam != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '✓ Posting as Team Application (Escrow paid by Team $_selectedTeam)',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppColors.brandCyan,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 14),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.outfit(color: AppColors.error, fontSize: 12),
                ),
              ),

            // Title
            AppTextField(
              controller: _titleCtrl,
              label: 'Job Title',
              hint: 'e.g. Design UI for Hackathon Pitch',
            ),
            const SizedBox(height: 12),

            // Category Dropdown
            Text('Category', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassStroke),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  dropdownColor: AppColors.bgCard,
                  items: _categories.map((c) {
                    final display = c
                        .split(' ')
                        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
                        .join(' ');
                    return DropdownMenuItem(value: c, child: Text(display, style: GoogleFonts.outfit(color: Colors.white)));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Description
            AppTextField(
              controller: _descCtrl,
              label: 'Full Description',
              hint: 'Provide details about the task, requirements, and deliverables...',
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // Line ID & Deadline
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _lineIdCtrl,
                    label: 'Your LINE ID',
                    hint: 'e.g. john_doe',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _deadlineCtrl,
                    label: 'Deadline',
                    hint: 'e.g. Tomorrow, 5 PM',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Difficulty Slider (1 to 5)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Difficulty: $_difficulty / 5', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
                Row(
                  children: [
                    for (int i = 1; i <= 5; i++)
                      Icon(
                        i <= _difficulty ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: AppColors.brandGold,
                        size: 20,
                      ),
                  ],
                ),
              ],
            ),
            Slider(
              value: _difficulty.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              activeColor: AppColors.brandGold,
              inactiveColor: AppColors.bgCard,
              onChanged: (v) => setState(() => _difficulty = v.round()),
            ),
            const SizedBox(height: 8),

            // Wage and Token
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    controller: _wageCtrl,
                    label: 'Escrow Wage Amount',
                    hint: 'e.g. 50.0',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Token', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassStroke),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: isTeam ? 'CSP' : _wageToken,
                            dropdownColor: AppColors.bgCard,
                            items: isTeam
                                ? const [
                                    DropdownMenuItem(value: 'CSP', child: Text('CSP', style: TextStyle(color: Colors.white))),
                                  ]
                                : const [
                                    DropdownMenuItem(value: 'CSP', child: Text('CSP', style: TextStyle(color: Colors.white))),
                                    DropdownMenuItem(value: 'BDP', child: Text('BDP', style: TextStyle(color: Colors.white))),
                                  ],
                            onChanged: isTeam
                                ? null
                                : (v) {
                                    if (v != null) setState(() => _wageToken = v);
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Available balance in ${isTeam ? "Team $_selectedTeam" : "Personal Wallet"}: ${balance.toStringAsFixed(2)} ${isTeam ? "CSP" : _wageToken}',
              style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),

            // Submit Button
            GradientButton(
              label: _submitting ? 'Creating Escrow...' : 'Submit & Lock Escrow',
              isLoading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JOB DETAILS MODAL (LINE CONTACT + SECRET CODE CLAIM + 10 CSP FINE PENALTY)
// ─────────────────────────────────────────────────────────────────────────────
class _JobDetailsModal extends StatefulWidget {
  const _JobDetailsModal({required this.job, required this.onClaimSuccess});
  final MarketplaceApplication job;
  final VoidCallback onClaimSuccess;

  @override
  State<_JobDetailsModal> createState() => _JobDetailsModalState();
}

class _JobDetailsModalState extends State<_JobDetailsModal> {
  final _codeCtrl = TextEditingController();
  bool _isClaiming = false;
  String? _claimError;
  String? _claimSuccessMessage;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _openLineApp(String lineId) async {
    final cleanId = lineId.replaceAll('@', '').trim();
    final urlString = 'https://line.me/ti/p/~$cleanId';
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        Clipboard.setData(ClipboardData(text: cleanId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open LINE app. LINE ID "$cleanId" copied!'),
            backgroundColor: AppColors.brandPurple,
          ),
        );
      }
    }
  }

  Future<void> _claimPayment() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty || code.length != 6) {
      setState(() => _claimError = 'Please enter a valid 6-digit secret code.');
      return;
    }

    final vm = context.read<WalletViewModel>();
    if (vm.currentAccountId == widget.job.creatorAccountId) {
      setState(() => _claimError = 'You cannot claim your own job application!');
      return;
    }

    setState(() {
      _isClaiming = true;
      _claimError = null;
      _claimSuccessMessage = null;
    });

    final res = await vm.marketplaceService.claimApplication(
      accountId: vm.currentAccountId!,
      jobId: widget.job.id,
      secretCode: code,
    );

    setState(() => _isClaiming = false);

    if (res.success) {
      await vm.refresh();
      if (mounted) {
        widget.onClaimSuccess();
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() {
        _claimError = res.error ?? 'Claim failed. Incorrect code entered.';
      });
      await vm.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final vm = context.watch<WalletViewModel>();
    final isMine = job.creatorAccountId == vm.currentAccountId;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.paddingOf(context).bottom +
              24,
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassStroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.title,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: job.isOpen
                        ? AppColors.brandCyan.withValues(alpha: 0.15)
                        : AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    job.status,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: job.isOpen ? AppColors.brandCyan : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Metadata row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    job.category.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandPurple,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Builder(
                  builder: (_) {
                    final isTeam = job.type == 'team application' ||
                        job.creatorAccountId.startsWith('Team:') ||
                        (job.creatorNickname?.startsWith('Team:') ?? false);
                    final isFaculty = job.type == 'faculty application';
                    final label = isTeam ? 'TEAM' : (isFaculty ? 'FACULTY' : 'STUDENT');
                    final color = isTeam
                        ? const Color(0xFF10B981)
                        : (isFaculty ? AppColors.brandPurple : AppColors.brandCyan);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: isTeam ? Border.all(color: color.withValues(alpha: 0.3)) : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isTeam) ...[
                            Icon(Icons.groups_rounded, size: 11, color: color),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            label,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'Difficulty: ${job.difficulty}/5',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.brandGold),
                ),
                const Spacer(),
                Text(
                  'Due: ${job.deadline.isNotEmpty ? job.deadline : "Flexible"}',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Wage info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ESCROW WAGE',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${job.wage} ${job.wageToken}',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.lock_clock_rounded, color: Colors.white, size: 32),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Full Job Description
            Text(
              'Job Description',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassStroke),
              ),
              child: SelectableText(
                job.description.isNotEmpty ? job.description : 'No description provided.',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // LINE Contact Button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF06C755).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF06C755).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF06C755),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contact Creator on LINE',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'LINE ID: ${job.lineId}',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06C755),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openLineApp(job.lineId),
                    child: Text('Open LINE', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Claim section (for applicants)
            if (job.isOpen && !isMine) ...[
              Text(
                'Claim Payment (Enter Secret Code)',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Once the employer is satisfied with your work, they will share the 6-digit code with you to unlock your payment.',
                style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),

              // Fine Warning Box
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.brandGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.brandGold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Entering the wrong code more than 3 times will result in a penalty fine of 10 CSP!',
                        style: GoogleFonts.outfit(fontSize: 11, color: AppColors.brandGold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_claimError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _claimError!,
                    style: GoogleFonts.outfit(color: AppColors.error, fontSize: 12),
                  ),
                ),

              if (_claimSuccessMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _claimSuccessMessage!,
                    style: GoogleFonts.outfit(color: AppColors.success, fontSize: 12),
                  ),
                ),

              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _codeCtrl,
                      hint: '6-digit code',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isClaiming ? null : _claimPayment,
                    child: _isClaiming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
                            'Claim Wage',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ] else if (isMine) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassStroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You are the creator of this application.',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brandCyan),
                    ),
                    if (job.secretCode != null) ...[
                      const SizedBox(height: 6),
                      Text('Secret Code: ${job.secretCode}',
                          style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ],
                ),
              ),
            ] else ...[
              Center(
                child: Text(
                  'This application has already been completed.',
                  style: GoogleFonts.outfit(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
        ),
      ),
    );
  }
}
