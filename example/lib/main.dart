import 'package:fl_chart_app/cubits/app/app_cubit.dart';
import 'package:fl_chart_app/presentation/resources/app_resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'presentation/router/app_router.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AppCubit>(create: (BuildContext context) => AppCubit()),
      ],
      child: MaterialApp.router(
        title: AppTexts.appName,
        theme: ThemeData(
          useMaterial3: true,
          textTheme: GoogleFonts.assistantTextTheme(
            Theme.of(context).textTheme.apply(
                  bodyColor: AppColors.mainTextColor3,
                ),
          ),
          scaffoldBackgroundColor: AppColors.pageBackground,
        ),
        darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            textTheme: GoogleFonts.assistantTextTheme(
                Theme.of(context).textTheme.apply(
                      bodyColor: AppColors.mainTextColor3,
                    ))),
        routerConfig: appRouterConfig,
      ),
    );
  }
}
