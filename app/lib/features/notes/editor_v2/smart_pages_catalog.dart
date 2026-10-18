/// Data-driven Smart Pages template library (10 categories × 20 templates).
class SmartPageTemplate {
  final String id;
  final String title;
  final String category;
  final String body;
  final String pageTemplate;

  const SmartPageTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.body,
    this.pageTemplate = 'lined',
  });
}

class SmartPagesCatalog {
  const SmartPagesCatalog._();

  static const Map<String, List<String>> _titles = {
    'Calendars': [
      'Monthly Calendar','Yearly Overview','Academic Calendar','Content Calendar','Family Calendar',
      'Work Calendar','Exam Calendar','Holiday Calendar','Project Calendar','Reading Calendar',
      'Fitness Calendar','Meal Calendar','Budget Calendar','Travel Calendar','Social Calendar',
      'Deadline Calendar','Appointment Calendar','Habit Calendar','Launch Calendar','Blank Calendar Grid',
    ],
    'To-do Lists': [
      'Daily To-do','Weekly To-do','Monthly To-do','Priority Matrix','Quick Tasks',
      'Errands List','Home Tasks','School Tasks','Work Tasks','Shopping List',
      'Packing Checklist','Cleaning Checklist','Digital Cleanup','Admin Tasks','Waiting On',
      'Delegated Tasks','Recurring Tasks','Someday / Maybe','Top Three Tasks','Task Brain Dump',
    ],
    'Planners': [
      'Daily Planner','Weekly Planner','Monthly Planner','Quarterly Planner','Yearly Planner',
      'Student Planner','Work Planner','Project Planner','Content Planner','Event Planner',
      'Travel Planner','Meal Planner','Study Planner','Revision Planner','Reading Planner',
      'Launch Planner','Meeting Planner','Goal Planner','Family Planner','Minimal Planner',
    ],
    'Routines & Habits': [
      'Morning Routine','Evening Routine','School Routine','Study Routine','Workout Routine',
      'Sleep Routine','Weekly Reset','Digital Detox','Habit Tracker','30-Day Challenge',
      'Water Tracker','Reading Streak','Meditation Tracker','Stretch Breaks','Screen-Time Log',
      'Self-care Routine','Chore Rotation','Focus Sessions','Consistency Tracker','Routine Builder',
    ],
    'Study & Learning': [
      'Study Session','Exam Revision','Subject Tracker','Assignment Tracker','Lecture Notes',
      'Cornell Notes','Flashcard Builder','Practice Log','Mistake Journal','Formula Sheet',
      'Vocabulary Log','Reading Notes','Research Notes','Lab Report','Essay Planner',
      'Presentation Planner','Course Dashboard','Weekly Study Review','Exam Countdown','Learning Journal',
    ],
    'Projects': [
      'Project Brief','Project Roadmap','Sprint Planner','Milestone Tracker','Task Breakdown',
      'Meeting Minutes','Decision Log','Risk Register','Bug Tracker','Feature Backlog',
      'Release Checklist','Project Retrospective','Team Stand-up','Requirements Sheet','User Research',
      'Design Review','Implementation Plan','QA Checklist','Project Status','Project Archive',
    ],
    'Health & Wellness': [
      'Mood Tracker','Workout Log','Walking Log','Sleep Log','Meal Journal',
      'Symptom Notes','Appointment Notes','Wellness Check-in','Energy Tracker','Mindfulness Log',
      'Fitness Goals','Recovery Notes','Healthy Habits','Weekly Wellness','Outdoor Time',
      'Personal Bests','Training Plan','Rest Day Notes','Self-care Menu','Progress Reflection',
    ],
    'Finance': [
      'Monthly Budget','Expense Tracker','Savings Goal','Subscription Audit','Bill Checklist',
      'No-spend Challenge','Shopping Budget','Income Log','Purchase Research','Debt Overview',
      'Emergency Fund','Travel Budget','School Budget','Gift Budget','Annual Costs',
      'Financial Goals','Cash Flow','Wishlist','Price Comparison','Money Review',
    ],
    'Goals & Reflection': [
      'Goal Breakdown','Quarterly Goals','Yearly Goals','Vision Board Notes','Weekly Review',
      'Daily Reflection','Gratitude Log','Wins Journal','Lessons Learned','Decision Journal',
      'Future Self Letter','Values Check-in','Personal Milestones','Monthly Review','End-of-Year Review',
      'Idea Parking Lot','Brain Dump','Problem Solving','Creative Prompts','Next Steps',
    ],
    'Lists & Trackers': [
      'Books to Read','Books Read','Watchlist','Places to Visit','Gift Ideas',
      'Recipe Collection','Favorite Quotes','Useful Links','People to Contact','Contacts Notes',
      'Inventory List','Home Maintenance','Device Maintenance','Backup Checklist','Open Questions',
      'Things to Learn','Ideas List','Resource Library','Comparison Table','Reference Sheet',
    ],
  };

  static List<SmartPageTemplate> get all => _titles.entries.expand((entry) {
    return entry.value.indexed.map((item) {
      final index = item.$1;
      final title = item.$2;
      final category = entry.key;
      return SmartPageTemplate(
        id: category.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-') + '-${index + 1}',
        title: title,
        category: category,
        body: _bodyFor(category, title),
        pageTemplate: category == 'To-do Lists' || category == 'Routines & Habits'
            ? 'checklist'
            : category == 'Calendars'
                ? 'grid'
                : category == 'Study & Learning'
                    ? 'cornell'
                    : 'lined',
      );
    });
  }).toList(growable: false);

  static String _bodyFor(String category, String title) {
    switch (category) {
      case 'Calendars':
        return 'MONTH / YEAR: ____________________\n\nMON   TUE   WED   THU   FRI   SAT   SUN\n1       2       3       4       5       6       7\n8       9      10     11     12     13     14\n15    16     17     18     19     20     21\n22    23     24     25     26     27     28\n29    30     31\n\nKEY DATES\n• ______________________________\n• ______________________________\n• ______________________________';
      case 'To-do Lists':
        return 'TOP PRIORITIES\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n\nTASKS\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n\nNOTES / WAITING ON\n________________________________\n________________________________';
      case 'Planners':
        return 'MAIN FOCUS\n________________________________\n\nPRIORITIES\n1. ______________________________\n2. ______________________________\n3. ______________________________\n\nSCHEDULE\n________________________________\n________________________________\n________________________________\n________________________________\n\nNOTES & NEXT STEPS\n________________________________\n________________________________';
      case 'Routines & Habits':
        return 'HABIT / ROUTINE: __________________\n\n☐ Mon   ☐ Tue   ☐ Wed   ☐ Thu\n☐ Fri     ☐ Sat    ☐ Sun\n\nMORNING\n☐ ______________________________\n☐ ______________________________\n\nEVENING / REVIEW\n☐ ______________________________\n☐ ______________________________\n\nSTREAK / NOTES: __________________';
      case 'Study & Learning':
        return 'SUBJECT: _________________________\nDATE: __________  TOPIC: __________\n\nKEY IDEAS\n________________________________\n________________________________\n________________________________\n\nQUESTIONS / EXAMPLES\n________________________________\n________________________________\n\nSUMMARY / WHAT TO REVISE\n________________________________\n________________________________';
      case 'Projects':
        return 'OBJECTIVE\n________________________________\n\nDELIVERABLES\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n\nMILESTONES / OWNER / DUE DATE\n________________________________\n________________________________\n\nRISKS / BLOCKERS\n________________________________\n\nNEXT ACTION\n________________________________';
      case 'Health & Wellness':
        return 'DATE: __________  CHECK-IN: ________\n\nENERGY: 1  2  3  4  5\nMOOD: ____________________________\nSLEEP / MOVEMENT / WATER\n________________________________\n________________________________\n\nNOTES & PATTERNS\n________________________________\n________________________________\n\nONE SMALL NEXT STEP\n________________________________';
      case 'Finance':
        return 'PERIOD: __________________________\n\nPLANNED      ACTUAL      DIFFERENCE\n__________   __________   __________\n__________   __________   __________\n__________   __________   __________\n__________   __________   __________\n\nTOTALS\nIncome: __________  Spending: _______\nSavings: __________\n\nNOTES / NEXT ACTION\n________________________________';
      case 'Goals & Reflection':
        return 'INTENTION\n________________________________\n\nWHAT WENT WELL?\n________________________________\n________________________________\n\nWHAT DID I LEARN?\n________________________________\n________________________________\n\nWHAT CAN I IMPROVE?\n________________________________\n________________________________\n\nNEXT SMALL STEP\n________________________________';
      default:
        return 'PURPOSE / CONTEXT\n________________________________\n\nITEMS / DETAILS\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n☐ ______________________________\n\nREFERENCE / LINKS\n________________________________\n________________________________\n\nNOTES\n________________________________';
    }
  }
}
